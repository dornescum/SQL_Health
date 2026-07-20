create table users (
    id int auto_increment primary key,
    uid char(32) not null,
    name varchar(100) not null,
    surname varchar(100) not null,
    email varchar(255) not null,
    sex tinyint null,
    country varchar(100) null,
    town varchar(100) null,
    password varchar(255) not null,
    role_id int default 6 null,
    created_at timestamp default CURRENT_TIMESTAMP null,
    updated_at timestamp default CURRENT_TIMESTAMP null on update CURRENT_TIMESTAMP,
    is_active tinyint(1) default 0 not null,
    soft_delete tinyint(1) default 0 not null,
    can_purchase_visits tinyint(1) default 1 not null comment 'Permission to purchase visits: 0=blocked, 1=allowed',
    blocked_reason varchar(255) null comment 'Reason for blocking purchases',
    blocked_at timestamp null comment 'When the user was blocked',
    blocked_by int null comment 'Admin user ID who blocked this user',
    is_dev tinyint(1) default 0 not null comment 'Dev/test account flag: 1=test account, excluded from reports and analytics',
    last_login_country char(2) null,
    constraint email unique (email),
    constraint uid unique (uid),
    constraint fk_users_blocked_by foreign key (blocked_by) references users (id) on delete
    set null,
        constraint fk_users_role_id foreign key (role_id) references roles (id) on update cascade on delete
    set null
);
create index idx_can_purchase_visits on users (can_purchase_visits);
create index idx_users_is_active on users (is_active);
create index idx_users_is_dev on users (is_dev);
create index idx_users_soft_delete on users (soft_delete);