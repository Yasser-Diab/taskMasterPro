-- Private birth date used for age-aware, non-medical coaching. Ownership
-- remains anchored to auth.uid() through profiles.user_id.

alter table public.profiles
  add column if not exists date_of_birth date;

alter table public.profiles
  drop constraint if exists profiles_date_of_birth_check;

alter table public.profiles
  add constraint profiles_date_of_birth_check
  check (
    date_of_birth is null
    or date_of_birth >= date '1900-01-01'
  );

comment on column public.profiles.date_of_birth is
  'Private date of birth for age-aware coaching. Never used as record ownership.';

create or replace function public.validate_profile_birth_date()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.date_of_birth is not null and new.date_of_birth > current_date then
    raise exception 'invalid_birth_date';
  end if;
  return new;
end;
$$;

drop trigger if exists validate_profile_birth_date_trigger
  on public.profiles;
create trigger validate_profile_birth_date_trigger
before insert or update of date_of_birth on public.profiles
for each row execute function public.validate_profile_birth_date();
