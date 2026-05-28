CREATE TABLE IF NOT EXISTS users
(
    id serial PRIMARY KEY,
    name text COLLATE pg_catalog."default" NOT NULL,
    expected_start_time time without time zone NOT NULL DEFAULT '09:00:00'::time without time zone,
    expected_stop_time time without time zone NOT NULL DEFAULT '18:00:00'::time without time zone,
    expected_days smallint NOT NULL DEFAULT 5,
    reg_date date NOT NULL DEFAULT CURRENT_DATE
);

CREATE TABLE IF NOT EXISTS user_cards
(
    id uuid PRIMARY KEY,
    user_id integer,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS user_exclusions
(
    id serial PRIMARY KEY,
    user_id integer,
    start_datetime timestamp without time zone,
    stop_datetime timestamp without time zone,
    type_exclusion text COLLATE pg_catalog."default",
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS time_log
(
    user_id integer NOT NULL,
    date date NOT NULL,
    start_time time without time zone,
    stop_time time without time zone,
    total_mins integer,
    is_late boolean,
    is_leave boolean,
    is_late_reason boolean,
    is_leave_reason boolean,
    PRIMARY KEY (user_id, date),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);