CREATE TABLE tbl1 (id bigserial primary key, col1 bigint);

INSERT INTO tbl1 (col1)
SELECT rnd FROM (SELECT generate_series(1,10000), (random() * 1000000)::bigint as rnd) a;

create table tbl2 ( like tbl1 INCLUDING ALL );
insert into tbl2 select * from tbl1;

CREATE INDEX on tbl2(col1);

create table small_tbl2 ( like tbl2 INCLUDING ALL );
insert into small_tbl2 select * from tbl2 LIMIT 10;

VACUUM FULL ANALYZE;