-- CARE 4 EVER - DATABASE FOUNDATION v1.0
-- STAGE 4: SERVICES, RATES, DUTY ROSTER, ASSIGNMENT & REPLACEMENT
-- Run after Stages 1, 2 and 3.

create type public.service_type as enum ('day','night','day_night','single_visit');
create type public.service_status as enum ('planned','active','on_hold','closed','cancelled');
create type public.duty_shift as enum ('day','night','single_visit');
create type public.duty_status as enum ('vacant','assigned','accepted','change_requested','journey_started','checked_in','in_progress','handover_pending','completed','cancelled','no_show');
create type public.assignment_status as enum ('assigned','accepted','change_requested','replaced','cancelled','completed');

create table public.client_services (
 id uuid primary key default gen_random_uuid(),
 client_id uuid not null references public.clients(id) on delete restrict,
 service_type public.service_type not null,
 start_date date not null,
 expected_end_date date,
 actual_end_date date,
 day_start_time time default '07:00',
 day_end_time time default '19:00',
 night_start_time time default '19:00',
 night_end_time time default '07:00',
 day_client_rate numeric(12,2) check(day_client_rate is null or day_client_rate>=0),
 night_client_rate numeric(12,2) check(night_client_rate is null or night_client_rate>=0),
 single_visit_rate numeric(12,2) check(single_visit_rate is null or single_visit_rate>=0),
 advance_required numeric(12,2) not null default 0 check(advance_required>=0),
 special_requirements text,
 status public.service_status not null default 'planned',
 closure_reason text,
 created_by uuid references public.profiles(id),
 created_at timestamptz not null default now(),
 updated_by uuid references public.profiles(id),
 updated_at timestamptz not null default now(),
 check(expected_end_date is null or expected_end_date>=start_date),
 check(actual_end_date is null or actual_end_date>=start_date)
);
create trigger client_services_set_updated_at before update on public.client_services for each row execute function public.set_updated_at();

create table public.client_service_rate_history (
 id uuid primary key default gen_random_uuid(),
 client_service_id uuid not null references public.client_services(id) on delete cascade,
 effective_from date not null,
 day_rate numeric(12,2) check(day_rate is null or day_rate>=0),
 night_rate numeric(12,2) check(night_rate is null or night_rate>=0),
 single_visit_rate numeric(12,2) check(single_visit_rate is null or single_visit_rate>=0),
 reason text,
 created_by uuid references public.profiles(id),
 created_at timestamptz not null default now(),
 unique(client_service_id,effective_from)
);

create table public.duties (
 id uuid primary key default gen_random_uuid(),
 client_id uuid not null references public.clients(id) on delete restrict,
 client_service_id uuid not null references public.client_services(id) on delete restrict,
 duty_date date not null,
 shift public.duty_shift not null,
 scheduled_start timestamptz not null,
 scheduled_end timestamptz not null,
 status public.duty_status not null default 'vacant',
 client_rate_snapshot numeric(12,2) check(client_rate_snapshot is null or client_rate_snapshot>=0),
 nurse_pay_snapshot numeric(12,2) check(nurse_pay_snapshot is null or nurse_pay_snapshot>=0),
 notes text,
 created_by uuid references public.profiles(id),
 created_at timestamptz not null default now(),
 updated_by uuid references public.profiles(id),
 updated_at timestamptz not null default now(),
 check(scheduled_end>scheduled_start),
 unique(client_service_id,duty_date,shift)
);
create trigger duties_set_updated_at before update on public.duties for each row execute function public.set_updated_at();

create table public.duty_assignments (
 id uuid primary key default gen_random_uuid(),
 duty_id uuid not null references public.duties(id) on delete cascade,
 nurse_id uuid not null references public.nurses(id) on delete restrict,
 status public.assignment_status not null default 'assigned',
 assigned_at timestamptz not null default now(),
 assigned_by uuid references public.profiles(id),
 responded_at timestamptz,
 response_note text,
 ended_at timestamptz,
 is_current boolean not null default true,
 created_at timestamptz not null default now()
);
create unique index one_current_assignment_per_duty on public.duty_assignments(duty_id) where is_current=true;

create table public.duty_replacements (
 id uuid primary key default gen_random_uuid(),
 duty_id uuid not null references public.duties(id) on delete cascade,
 previous_assignment_id uuid not null references public.duty_assignments(id) on delete restrict,
 replacement_assignment_id uuid not null references public.duty_assignments(id) on delete restrict,
 reason text not null,
 remarks text,
 replaced_by uuid references public.profiles(id),
 replaced_at timestamptz not null default now(),
 check(previous_assignment_id<>replacement_assignment_id)
);

create index client_services_client_idx on public.client_services(client_id);
create index client_services_status_idx on public.client_services(status);
create index duties_date_shift_idx on public.duties(duty_date,shift);
create index duties_client_idx on public.duties(client_id);
create index duty_assignments_nurse_idx on public.duty_assignments(nurse_id);

alter table public.client_services enable row level security;
alter table public.client_service_rate_history enable row level security;
alter table public.duties enable row level security;
alter table public.duty_assignments enable row level security;
alter table public.duty_replacements enable row level security;

create policy "Admin manage client services" on public.client_services for all to authenticated using(public.current_user_role()='admin') with check(public.current_user_role()='admin');
create policy "Admin manage rate history" on public.client_service_rate_history for all to authenticated using(public.current_user_role()='admin') with check(public.current_user_role()='admin');
create policy "Admin manage duties" on public.duties for all to authenticated using(public.current_user_role()='admin') with check(public.current_user_role()='admin');
create policy "Admin manage duty assignments" on public.duty_assignments for all to authenticated using(public.current_user_role()='admin') with check(public.current_user_role()='admin');
create policy "Admin manage duty replacements" on public.duty_replacements for all to authenticated using(public.current_user_role()='admin') with check(public.current_user_role()='admin');

create policy "Coordinator manage client services" on public.client_services for all to authenticated using(public.current_user_role()='coordinator') with check(public.current_user_role()='coordinator');
create policy "Coordinator view rate history" on public.client_service_rate_history for select to authenticated using(public.current_user_role()='coordinator');
create policy "Coordinator manage duties" on public.duties for all to authenticated using(public.current_user_role()='coordinator') with check(public.current_user_role()='coordinator');
create policy "Coordinator manage duty assignments" on public.duty_assignments for all to authenticated using(public.current_user_role()='coordinator') with check(public.current_user_role()='coordinator');
create policy "Coordinator manage duty replacements" on public.duty_replacements for all to authenticated using(public.current_user_role()='coordinator') with check(public.current_user_role()='coordinator');

create policy "Nurse view own duties" on public.duties for select to authenticated using(exists(select 1 from public.duty_assignments da join public.nurses n on n.id=da.nurse_id where da.duty_id=duties.id and da.is_current=true and n.auth_user_id=auth.uid()));
create policy "Nurse view own assignments" on public.duty_assignments for select to authenticated using(exists(select 1 from public.nurses n where n.id=duty_assignments.nurse_id and n.auth_user_id=auth.uid()));

create policy "Family view own services" on public.client_services for select to authenticated using(exists(select 1 from public.client_family_contacts cfc where cfc.client_id=client_services.client_id and cfc.auth_user_id=auth.uid() and cfc.family_portal_access=true and cfc.active=true));
create policy "Family view own duties" on public.duties for select to authenticated using(exists(select 1 from public.client_family_contacts cfc where cfc.client_id=duties.client_id and cfc.auth_user_id=auth.uid() and cfc.family_portal_access=true and cfc.active=true));

create policy "Accounts view client services" on public.client_services for select to authenticated using(public.current_user_role()='accounts');
create policy "Accounts view rate history" on public.client_service_rate_history for select to authenticated using(public.current_user_role()='accounts');
create policy "Accounts view duties" on public.duties for select to authenticated using(public.current_user_role()='accounts');
