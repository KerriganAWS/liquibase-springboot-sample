--liquibase formatted sql
--changeset demo:02
--comment: insert some test data

insert into test_data values (UUID(), 'key1','value1');
insert into test_data values (UUID(), 'key2','value2');
