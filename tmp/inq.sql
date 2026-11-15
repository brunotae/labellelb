-- LA Belle LB · 문의 관리 통합 (브랜드사 협업 문의) · 여러 번 실행해도 안전합니다.
-- 1) 새 입력 항목
alter table public.labelle_inquiries add column if not exists brand text;
alter table public.labelle_inquiries add column if not exists email text;
alter table public.labelle_inquiries add column if not exists phone text;
alter table public.labelle_inquiries add column if not exists product_category text;
alter table public.labelle_inquiries add column if not exists target_countries text;
alter table public.labelle_inquiries add column if not exists privacy_agreed boolean not null default false;

-- 2) 상태 4단계: 접수 · 검토 · 협의 · 완료
alter table public.labelle_inquiries drop constraint if exists labelle_inquiries_status_check;
update public.labelle_inquiries set status = case status when '답변대기' then '접수' when '답변완료' then '완료' else status end;
alter table public.labelle_inquiries alter column status set default '접수';
alter table public.labelle_inquiries add constraint labelle_inquiries_status_check check (status in ('접수','검토','협의','완료'));

-- 3) 문의 유형 정리 (기존 문의도 새 유형으로)
update public.labelle_inquiries set category = case category
  when '글로벌 뷰티 유통·브랜드' then 'K-뷰티 브랜드 입점·해외 유통'
  when '병원·클리닉 협력' then '의료기관·의료관광 제휴'
  when '공간·오픈 컨설팅' then '기타 비즈니스 협업'
  when '정부·기관 협력' then '기타 비즈니스 협업'
  when '기타' then '기타 비즈니스 협업'
  else category end;
update public.labelle_inquiries set email = trim(contact) where email is null and contact ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$';

-- 4) 방문자 접수 규칙: 개인정보 동의 필수, 길이 제한, 상태는 항상 '접수'로 시작
drop policy if exists "inq insert" on public.labelle_inquiries;
create policy "inq insert" on public.labelle_inquiries for insert to anon, authenticated with check (
  status = '접수' and admin_note is null and answered_at is null and privacy_agreed is true
  and char_length(name) between 1 and 60
  and char_length(contact) between 3 and 120
  and (email is null or (char_length(email) between 5 and 120 and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'))
  and coalesce(char_length(phone), 0) <= 40
  and coalesce(char_length(brand), 0) <= 80
  and coalesce(char_length(product_category), 0) <= 60
  and coalesce(char_length(target_countries), 0) <= 200
  and char_length(title) between 1 and 100
  and char_length(message) between 1 and 3000
  and coalesce(char_length(company), 0) <= 80
  and (attachments is null or (jsonb_typeof(attachments) = 'array' and jsonb_array_length(attachments) <= 3))
);

-- 5) 첨부파일: 비공개 보관, 10MB, 문서·이미지·ZIP 확장자만 (열람·삭제는 관리자만)
update storage.buckets set public = false, file_size_limit = 10485760 where id = 'labelle-inquiry-files';
drop policy if exists "labelle inq file upload" on storage.objects;
create policy "labelle inq file upload" on storage.objects for insert to anon, authenticated with check (
  bucket_id = 'labelle-inquiry-files'
  and lower(storage.extension(name)) in ('pdf','ppt','pptx','key','doc','docx','hwp','xls','xlsx','jpg','jpeg','png','zip')
);

select status, category, count(*) from public.labelle_inquiries group by 1,2 order by 1,2;
