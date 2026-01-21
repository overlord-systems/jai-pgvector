# Jai Pgvector

A handler for [Jaipg](https://github.com/rluba/jai-postgres) that adds support for the pgvector extension.

## Usage

```c
#import "Basic";
#import "Jaipg";
#import "Jaipgvector";

My_Table :: struct {
    id: s64;

    // All the following are VALID member types to parse/accept a pgvector 'vector' type.
    // Note that if you use a fixed-size array, like the last example, your array size MUST match the number of dimensions of your DB 'vector' column.
    embedding: []float;
    // embedding: [..]float;
    // embedding: [1536]float;
}

main :: () {
    db_url := "postgresql://postgres:postgres@localhost:5432/my_db";

    pg_conn, success := connect(db_url);
    if !success {
        print("failed to connect to postgres\n");
        exit(1);
    }
    defer disconnect(pg_conn);

  err_msg := register_pgvector_handler(pg_conn);
  if err_msg {
      print("registering pgvector handler failed. Err=%\n", err_msg);
      exit(1);
  }

  // Do queries normally and 'vector' columns will be placed in []float/[..]float/[N]float member fields of your structs
}
```
