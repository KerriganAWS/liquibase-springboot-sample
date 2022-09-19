--liquibase formatted sql
--changeset demo:01
--comment: create demo table

create table test_data
(
    id           varchar(45)  not null primary key,
    name         varchar(45)  not null,
    value        varchar(45)
)