alter table public.contacts
add column source_precedence smallint not null default 0
check (source_precedence >= 0);

comment on column public.contacts.source_precedence is
  'Higher-precedence source exports may update lower-precedence rows; base reruns cannot overwrite dated corrections.';
