-- Sanor English World : Supabase schema (v1)
-- รันทั้งไฟล์ใน Supabase > SQL Editor ครั้งเดียว (ใช้ได้ซ้ำโดยไม่พัง)
-- เก็บเฉพาะข้อมูลที่แอปใช้ตอนนี้: รหัสนักเรียน ห้อง ภาคเรียน บรรทัดผลการเรียน (คะแนน ถูก/ผิดรายข้อ ความพึงพอใจ) วันที่
-- ไม่เก็บชื่อจริง เสียง หรือข้อความที่นักเรียนพิมพ์

-- ===== ตาราง =====
create table if not exists public.students (
  student_code    text primary key check (student_code ~ '^[a-z0-9_-]{1,12}$'),
  user_id         uuid references auth.users(id) on delete set null,
  room            text,
  consent_version text not null,
  consented_at    timestamptz not null default now()
);

create table if not exists public.submissions (
  id           bigint generated always as identity primary key,
  student_code text not null references public.students(student_code) on delete cascade,
  room         text,
  term         text,
  report_line  text not null check (length(report_line) between 20 and 8000),
  created_at   timestamptz not null default now(),
  -- รหัสในบรรทัดผลต้องตรงกับรหัสนักเรียนที่ล็อกอิน (กันส่งแทนคนอื่น)
  constraint line_matches_code check (lower(split_part(report_line, ';', 2)) = student_code)
);
create index if not exists submissions_code_time on public.submissions (student_code, created_at desc);

-- ===== ฟังก์ชันช่วย =====
-- รหัสนักเรียนของคนที่ล็อกอิน = ส่วนหน้า @ ของอีเมลสมมติ (ผู้ใช้แก้เองไม่ได้)
create or replace function public.jwt_code() returns text
language sql stable as $$ select lower(split_part(coalesce(auth.jwt() ->> 'email', ''), '@', 1)) $$;

create or replace function public.is_teacher() returns boolean
language sql stable as $$ select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'teacher' $$;

-- สมัครใช้งาน: ผูกบัญชีกับรหัสนักเรียน (ใช้ซ้ำได้หลังครูลบบัญชีเก่าเพื่อรีเซ็ตรหัสผ่าน)
create or replace function public.register_student(p_room text, p_consent text) returns void
language plpgsql security definer set search_path = public as $$
declare c text := public.jwt_code();
begin
  if auth.uid() is null or c = '' or c !~ '^[a-z0-9_-]{1,12}$' then
    raise exception 'not signed in';
  end if;
  insert into public.students (student_code, user_id, room, consent_version)
  values (c, auth.uid(), left(p_room, 10), left(p_consent, 20))
  on conflict (student_code) do update
    set user_id = excluded.user_id, room = excluded.room
    where public.students.user_id is null or public.students.user_id = auth.uid();
  if not found then raise exception 'code already registered'; end if;
end $$;
revoke all on function public.register_student(text, text) from public, anon;
grant execute on function public.register_student(text, text) to authenticated;

-- ===== Row Level Security =====
alter table public.students    enable row level security;
alter table public.submissions enable row level security;

drop policy if exists students_select  on public.students;
drop policy if exists sub_insert       on public.submissions;
drop policy if exists sub_select       on public.submissions;

create policy students_select on public.students for select to authenticated
  using (student_code = public.jwt_code() or public.is_teacher());

create policy sub_insert on public.submissions for insert to authenticated
  with check (student_code = public.jwt_code()
              and exists (select 1 from public.students s
                          where s.student_code = public.jwt_code() and s.user_id = auth.uid()));

create policy sub_select on public.submissions for select to authenticated
  using (student_code = public.jwt_code() or public.is_teacher());

-- ไม่มี policy update/delete สำหรับนักเรียน = นักเรียนแก้หรือลบผลที่ส่งแล้วไม่ได้
-- ครูแก้/ลบ/ส่งออกผ่าน Supabase Dashboard (Table Editor) ซึ่งข้าม RLS ได้อยู่แล้ว

revoke all on public.students, public.submissions from anon;
grant select on public.students to authenticated;
grant select, insert on public.submissions to authenticated;

-- ครูล่าสุดต่อคนต่อภาคเรียน (ดูใน Table Editor / ส่งออก CSV)
create or replace view public.latest_submissions with (security_invoker = true) as
  select distinct on (student_code, term) student_code, room, term, report_line, created_at
  from public.submissions order by student_code, term, created_at desc;
grant select on public.latest_submissions to authenticated;

-- ===== ตั้งบัญชีครู (แก้อีเมลให้เป็นของท่าน แล้วรันแยกหลังสมัครบัญชีครู) =====
-- update auth.users set raw_app_meta_data = coalesce(raw_app_meta_data,'{}'::jsonb) || '{"role":"teacher"}'::jsonb
--   where email = 'อีเมลของครู@example.com';
