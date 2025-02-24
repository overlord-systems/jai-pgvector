# jai-pgvector
A handler for [Jaipg](https://github.com/rluba/jai-postgres) that adds support for the pgvector extension.

## Usage

```c
#import "Basic";
#import "Jaipg";
#import "Jaipgvector";

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
}
```
