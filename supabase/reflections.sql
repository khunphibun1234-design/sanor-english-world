-- Sanor English World : ตารางสะท้อนตนเอง (reflections) — รันใน Supabase > SQL Editor หนึ่งครั้ง (ใช้ซ้ำได้โดยไม่พัง)
-- ต้องรัน schema.sql มาก่อนแล้ว (ใช้ตาราง students และฟังก์ชัน jwt_code / is_teacher)
-- เก็บเฉพาะตัวเลือกที่นักเรียนกด (ไม่มีข้อความที่พิมพ์): รู้สึกอย่างไร / อยากฝึกส่วนไหน / จะฝึกอีกเมื่อไหร่

create table if not exists public.reflections (
  id           bigint generated always as identity primary key,
  student_code text not null references public.students(student_code) on delete cascade,
  room         text,
  term         text,
  topic_id     smallint not null check (topic_id between 1 and 25),
  feel         text not null check (feel  in ('u','a','n')),               -- u เข้าใจแล้ว / a เกือบเข้าใจ / n ต้องฝึกอีก
  focus        text not null check (focus in ('words','listen','speak','talk','read','write','quiz')),
  plan         text not null check (plan  in ('t','m','w')),               -- t วันนี้ / m พรุ่งนี้ / w สุดสัปดาห์
  created_at   timestamptz not null default now()
);
create index if not exists reflections_code_time on public.reflections (student_code, created_at desc);

alter table public.reflections enable row level security;
drop policy if exists refl_insert on public.reflections;
drop policy if exists refl_select on public.reflections;

create policy refl_insert on public.reflections for insert to authenticated
  with check (student_code = public.jwt_code()
              and exists (select 1 from public.students s
                          where s.student_code = public.jwt_code() and s.user_id = auth.uid()));
create policy refl_select on public.reflections for select to authenticated
  using (student_code = public.jwt_code() or public.is_teacher());

revoke all on public.reflections from anon;
grant select, insert on public.reflections to authenticated;

-- ล่าสุดต่อคนต่อภาคเรียนต่อหัวข้อ (ดู/ส่งออก CSV ใน Table Editor)
create or replace view public.latest_reflections with (security_invoker = true) as
  select distinct on (student_code, term, topic_id) student_code, room, term, topic_id, feel, focus, plan, created_at
  from public.reflections order by student_code, term, topic_id, created_at desc;
grant select on public.latest_reflections to authenticated;
