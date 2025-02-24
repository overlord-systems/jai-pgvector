#import "Jaipg";
#import "Basic";

register_pgvector_handler :: (pg_conn: PGconn) -> (err_msg: string) {

    Pgvector_Oids :: struct {
        vector_oid: Oid;
    }

    // @TODO: We currently only handle the vector type. Note that '_vector' means vector[].
    //
    // SELECT to_regtype('vector')::oid, to_regtype('_vector')::oid, to_regtype('halfvec')::oid, to_regtype('_halfvec')::oid, to_regtype('sparsevec')::oid, to_regtype('_sparsevec')::oid

    QUERY :: #string JAI
SELECT to_regtype('vector')::oid AS "vector_oid"
JAI

    rows: []Pgvector_Oids;
    rows=, success := execute(*pg_conn, Pgvector_Oids, QUERY);
    if !success return "failed to run postgres query to get pgvector OIDs";

    if rows.count == 0 return "no rows returned when querying pgvector OIDs. Do you have pgvector installed and activated on this database?";

    result := rows[0];
    if result.vector_oid == 0 return "no 'vector' type OID found. Do you have pgvector installed and activated on this database?";

    success = register_pg_type_handler(result.vector_oid, "vector", pgvector_vector_handler);
    if !success return "got pgvector OIDs from DB but registering them with Jaipg failed. Do you already have a pgvector handler registered?";

    return "";
}

#scope_module

pgvector_vector_handler :: (name: string, info: *Type_Info, slot: *u8, col_type: Pq_Type, len: int, data: *u8, row: int, col: int) -> bool {

    if info.type != .ARRAY {
        log_error("Error: Trying to write column % of type % into member field \"%\" of type %. Vectors can only be stored in member fields that are arrays of floats or views of floats", col, col_type, name, info.type);
        return false;
    }

    array_info := cast(*Type_Info_Array) info;
    if array_info.element_type.type != Type_Info_Tag.FLOAT {
        log_error("Error: Trying to write vector column % into member field \"%\" of type %. Member field must be a float array or view", col, name, info.type);
        return false;
    }

    vector_bytes: []u8 = .{count=len, data=data};
    element_size := array_info.element_type.runtime_size;
    dims := pgvector_get_dims_from_vector_bytes(vector_bytes);
    if element_size != 4 {
        log_error("Error: Trying to write column % of type % with array count % into member field \"%\" with array element size of % instead of 4. Member field must be a float array or view.", col, col_type, dims, name, element_size);
    }

    if array_info.array_type == .VIEW {

        view := (cast(*Array_View_64) slot);
        
        floats := pgvector_vector_bytes_to_floats(vector_bytes);
        
        view.count = floats.count;
        view.data = floats.data.(*u8);

    } else if array_info.array_count == -1 {

        resizable_array := cast(*Resizable_Array) slot;

        array_reserve(resizable_array, dims, element_size);
        resizable_array.count = dims;

        pgvector_vector_bytes_to_floats_buf(vector_bytes, .{count=dims, data=resizable_array.data.(*float)});

    } else {
        
        if array_info.array_count != dims {
            log_error("Error: Trying to write column % of type % with array count % into member field \"%\", which is a fixed-size array with count %. For fixed-size arrays, the size must match!", col, col_type, dims, name, array_info.array_count);
            return false;
        }
        
        pgvector_vector_bytes_to_floats_buf(vector_bytes, .{count=dims, data=slot.(*float)});
    }

    return true;
}

pgvector_get_dims_from_vector_bytes :: (vector: []u8) -> u16 {
    assert(vector.count >= 2);
    dims := ntoh(vector.data.(*u16).*);
    return dims;
}

pgvector_vector_bytes_to_floats :: (vector: []u8) -> []float {

    dims := pgvector_get_dims_from_vector_bytes(vector);

    out: [..]float;
    array_reserve(*out, dims);
    out.count = dims;

    pgvector_vector_bytes_to_floats_buf(vector, out);
    return out;
}

// This parses the input bytes and writes to the 'out' buffer.
// Note that its required that: out.count == pgvector_get_dims_from_vector_bytes(vector) 
pgvector_vector_bytes_to_floats_buf :: (vector: []u8, out: []float) {

    // At least as of pgvector 0.8.0, when responding in binary mode, pgvector prefixes
    // the float array with two int16, the first being the number of dimensions, and the second unused (always zero).
    //
    // Therefore, to parse it 8 bytes are the minimum (4 bytes dim+unused, 4 bytes first element).
    //
    // https://github.com/pgvector/pgvector/blob/fef635c9e5512597621e5669dce845c744170822/src/vector.c#L402
    assert(vector.count >= 4);

    dims := pgvector_get_dims_from_vector_bytes(vector);
    assert(out.count == dims, "'out' view used in pgvector_vector_bytes_to_floats must match vector dimensions");

    float_index := 0;
    float_ptr := vector.data.(*float) + 1; // +1 to skip the dims+unused at the beginning
    while float_index < dims {

        defer float_index += 1;

        // Incoming bytes are usually big endian, so this (from Jaipq) takes care of swapping bytes if our machine
        // is little endian.
        val := ntoh((float_ptr+float_index).*);

        out[float_index] = val;
    }
}
