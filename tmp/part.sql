-- LA Belle LB · 브랜드 제휴 / 비즈니스 협업 문의 분리 + 관리 기능 · 여러 번 실행해도 안전합니다.
alter table public.labelle_inquiries add column if not exists form text;
alter table public.labelle_inquiries add column if not exists website text;
alter table public.labelle_inquiries add column if not exists assignee text;
alter table public.labelle_inquiries add column if not exists history jsonb not null default '[]'::jsonb;
alter table public.labelle_inquiries add column if not exists source text not null default 'labellelb.com';
alter table public.labelle_inquiries add column if not exists external_ref text;   -- 리셋미 등 외부 시스템 연동용
alter table public.labelle_inquiries add column if not exists mailed_at timestamptz;
alter table public.labelle_inquiries alter column name drop not null;

-- 구분: brand(브랜드 입점·해외 유통) / business(비즈니스 협업)
update public.labelle_inquiries set form = case when category = 'K-뷰티 브랜드 입점·해외 유통' then 'brand' else 'business' end where form is null;
alter table public.labelle_inquiries drop constraint if exists labelle_inquiries_form_check;
alter table public.labelle_inquiries add constraint labelle_inquiries_form_check check (form in ('brand','business'));
update public.labelle_inquiries set category = '의료기관·외국인환자 유치 제휴' where category = '의료기관·의료관광 제휴';

-- 진행 상태: 신규 접수 → 검토 중 → 협의 중 → 완료
alter table public.labelle_inquiries drop constraint if exists labelle_inquiries_status_check;
update public.labelle_inquiries set status = case status when '접수' then '신규 접수' when '검토' then '검토 중' when '협의' then '협의 중' when '답변대기' then '신규 접수' when '답변완료' then '완료' else status end;
alter table public.labelle_inquiries alter column status set default '신규 접수';
alter table public.labelle_inquiries add constraint labelle_inquiries_status_check check (status in ('신규 접수','검토 중','협의 중','완료'));

-- 방문자 접수 규칙
drop policy if exists "inq insert" on public.labelle_inquiries;
create policy "inq insert" on public.labelle_inquiries for insert to anon, authenticated with check (
  status = '신규 접수' and admin_note is null and answered_at is null and assignee is null and mailed_at is null
  and history = '[]'::jsonb and privacy_agreed is true and form in ('brand','business') and source = 'labellelb.com'
  and char_length(company) between 1 and 80
  and (form = 'business' or char_length(name) between 1 and 60)
  and coalesce(char_length(name), 0) <= 60
  and char_length(email) between 5 and 120 and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
  and char_length(contact) between 3 and 120
  and coalesce(char_length(phone), 0) <= 40
  and coalesce(char_length(brand), 0) <= 80
  and coalesce(char_length(product_category), 0) <= 100
  and coalesce(char_length(target_countries), 0) <= 200
  and coalesce(char_length(website), 0) <= 300
  and char_length(title) between 1 and 100
  and (form = 'brand' or char_length(message) >= 1) and char_length(message) <= 3000
  and (attachments is null or (jsonb_typeof(attachments) = 'array' and jsonb_array_length(attachments) <= 3))
);

-- 첨부파일: 20MB, 문서·이미지·ZIP만, 비공개
update storage.buckets set public = false, file_size_limit = 20971520 where id = 'labelle-inquiry-files';

-- 새 문의 → 메일 발송 함수 호출 (함수가 없거나 메일 키가 없으면 아무 일도 하지 않음)
create or replace function public.labelle_inquiry_mail() returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform net.http_post(url := 'https://agdqlnaedojcgivwluty.supabase.co/functions/v1/labelle-inquiry-mail',
    body := jsonb_build_object('id', new.id), headers := '{"Content-Type":"application/json"}'::jsonb);
  return new;
exception when others then return new;
end $$;
drop trigger if exists labelle_inquiry_mail on public.labelle_inquiries;
create trigger labelle_inquiry_mail after insert on public.labelle_inquiries for each row execute function public.labelle_inquiry_mail();

select form, status, category, count(*) from public.labelle_inquiries group by 1,2,3 order by 1,2,3;
