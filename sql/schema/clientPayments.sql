create table client_payments (
    payment_id int auto_increment primary key,
    visit_id int not null,
    user_id int not null,
    visit_type enum ('1', '2') not null,
    visit_paid tinyint(1) default 0 null,
    amount decimal(10, 2) not null,
    payment_date datetime null,
    payment_intent_id varchar(255) null,
    payment_status enum ('pending', 'completed', 'failed', 'refunded') default 'pending' null,
    currency varchar(3) default 'EUR' null,
    currency_exchange_rate decimal(10, 6) default 1.000000 null,
    session_id varchar(255) not null,
    payment_method varchar(50) null,
    notes text null,
    created_at timestamp default CURRENT_TIMESTAMP null,
    updated_at timestamp default CURRENT_TIMESTAMP null on update CURRENT_TIMESTAMP,
    constraint visit_id unique (visit_id),
    constraint fk_payments_user_id foreign key (user_id) references users (id) on delete cascade,
    constraint fk_payments_visit_id foreign key (visit_id) references visits (visit_id) on delete cascade
) comment 'Simplified payment tracking: one payment per visit (1:1 relationship)';
create index idx_payment_date on client_payments (payment_date);
create index idx_payment_status on client_payments (payment_status);
create index idx_user_id on client_payments (user_id);
create index idx_visit_paid on client_payments (visit_paid);
create index idx_visit_type on client_payments (visit_type);