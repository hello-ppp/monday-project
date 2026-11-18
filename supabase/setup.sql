-- 먼데이프로젝트 사진첩 — Supabase 설정
-- Supabase 대시보드 > SQL Editor 에 붙여넣고 한 번 실행하면 됩니다.
-- 마지막 줄의 'CHANGE-ME' 를 원하는 관리자 비밀번호로 바꾼 뒤 실행하세요.

set search_path = public, extensions;
create extension if not exists pgcrypto with schema extensions;

-- 1) 사진 목록 (누구나 읽기만 가능)
create table if not exists public.photos (
  id          uuid primary key default gen_random_uuid(),
  path        text not null check (char_length(path) between 5 and 200),
  day         text not null default 'd16' check (day in ('d14','d16')),
  who         text not null check (char_length(who) between 1 and 30),
  caption     text not null default '' check (char_length(caption) <= 80),
  w           int  not null default 0,
  h           int  not null default 0,
  created_at  timestamptz not null default now()
);
alter table public.photos enable row level security;
drop policy if exists "photos are public" on public.photos;
create policy "photos are public" on public.photos for select using (true);
-- 쓰기·삭제 정책은 일부러 만들지 않음: 아래 함수로만 가능

-- 2) 삭제 열쇠 (아무도 직접 읽을 수 없음)
create table if not exists public.photo_keys (
  photo_id  uuid primary key references public.photos(id) on delete cascade,
  key_hash  text not null
);
alter table public.photo_keys enable row level security;

create table if not exists public.settings (
  k text primary key,
  v text not null
);
alter table public.settings enable row level security;

-- 3) 사진 등록: 올린 사람만 아는 열쇠의 해시를 함께 저장
create or replace function public.add_photo(
  p_path text, p_day text, p_who text, p_caption text, p_w int, p_h int, p_key_hash text
) returns uuid
language plpgsql security definer set search_path = public as $$
declare new_id uuid;
begin
  if p_path !~ '^uploads/[A-Za-z0-9_\-]+\.(jpg|jpeg|png|webp|gif)$' then
    raise exception 'bad path';
  end if;
  if (select count(*) from photos where created_at > now() - interval '1 minute') > 60 then
    raise exception 'slow down';
  end if;
  insert into photos(path, day, who, caption, w, h)
  values (p_path, coalesce(p_day,'d16'), left(trim(p_who),30), left(coalesce(p_caption,''),80),
          greatest(0,least(coalesce(p_w,0),10000)), greatest(0,least(coalesce(p_h,0),10000)))
  returning id into new_id;
  insert into photo_keys(photo_id, key_hash) values (new_id, p_key_hash);
  return new_id;
end $$;

-- 4) 삭제: 올린 사람 열쇠 또는 관리자 비밀번호가 맞을 때만
create or replace function public.delete_photo(p_id uuid, p_key text)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare ok boolean;
begin
  select exists(
    select 1 from photo_keys where photo_id = p_id and key_hash = encode(digest(p_key,'sha256'),'hex')
  ) or exists(
    select 1 from settings where k = 'admin_hash' and v = encode(digest(p_key,'sha256'),'hex')
  ) into ok;
  if not ok then return false; end if;
  delete from photos where id = p_id;
  return true;
end $$;

-- 관리자 비밀번호 확인용
create or replace function public.check_admin(p_key text)
returns boolean
language sql security definer set search_path = public, extensions as $$
  select exists(select 1 from settings where k='admin_hash' and v = encode(digest(p_key,'sha256'),'hex'));
$$;

revoke all on function public.add_photo(text,text,text,text,int,int,text) from public;
revoke all on function public.delete_photo(uuid,text) from public;
revoke all on function public.check_admin(text) from public;
grant execute on function public.add_photo(text,text,text,text,int,int,text) to anon, authenticated;
grant execute on function public.delete_photo(uuid,text) to anon, authenticated;
grant execute on function public.check_admin(text) to anon, authenticated;

-- 5) 사진 파일 저장소: 누구나 보기 + 올리기 (이미지, 10MB 이하)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', true, 10485760, array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do update set public = true, file_size_limit = 10485760,
  allowed_mime_types = array['image/jpeg','image/png','image/webp','image/gif'];

drop policy if exists "anyone can upload photos" on storage.objects;
create policy "anyone can upload photos" on storage.objects
  for insert to anon, authenticated
  with check (bucket_id = 'photos' and name like 'uploads/%');

-- 6) 실시간 반영
do $$ begin
  alter publication supabase_realtime add table public.photos;
exception when others then null; end $$;

-- 7) 관리자 비밀번호 (바꿔서 실행!)
insert into public.settings(k, v)
values ('admin_hash', encode(digest('CHANGE-ME','sha256'),'hex'))
on conflict (k) do update set v = excluded.v;
