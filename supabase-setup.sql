-- Supabase SQL Editor에서 한 번 실행하세요.
-- 온라인 예약 신청 저장용 테이블 + 익명(anon) INSERT만 허용

create table if not exists public.reservation_requests (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  name text not null,
  phone text not null,
  email text,
  meal_time text not null,
  preferred_date date not null,
  guests smallint not null,
  note text,
  privacy_agreed boolean not null default false
);

alter table public.reservation_requests enable row level security;

-- 웹(anon 키)에서 행 추가만 가능. 조회/수정/삭제는 대시보드(service role) 또는 인증 사용자 정책으로 별도 구성하세요.
drop policy if exists "anon_insert_reservation_requests" on public.reservation_requests;
create policy "anon_insert_reservation_requests"
  on public.reservation_requests
  for insert
  to anon
  with check (true);

-- admin.html: Supabase Auth로 로그인한 사용자만 예약 목록 조회 가능.
-- [관리자 계정 만들기 — 둘 중 하나]
--  A) 대시보드: Authentication → Users → Add user → Create new user (이메일·비밀번호, 필요 시 Auto Confirm)
--  B) 회원가입 API: admin-signup.html 열기 → ADMIN_INVITE_CODE 설정 후 폼으로 signUp (Authentication → Providers에서 Email ON)
drop policy if exists "authenticated_select_reservation_requests" on public.reservation_requests;
create policy "authenticated_select_reservation_requests"
  on public.reservation_requests
  for select
  to authenticated
  using (true);

-- 예약 처리 상태 (대시보드 통계·필터·상태 변경)
alter table public.reservation_requests
  add column if not exists status text not null default 'pending';

alter table public.reservation_requests
  drop constraint if exists reservation_requests_status_check;

alter table public.reservation_requests
  add constraint reservation_requests_status_check
  check (status in ('pending', 'confirmed', 'cancelled', 'completed'));

-- ========== 직원 역할 (관리자 / 운영자) — admin.html 팀원 등록 + Edge Function staff-invite ==========
create table if not exists public.staff_roles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  role text not null check (role in ('admin', 'operator')),
  created_at timestamptz not null default now()
);

create index if not exists staff_roles_role_idx on public.staff_roles (role);

alter table public.staff_roles enable row level security;

-- 같은 테이블을 RLS 정책 안에서 직접 서브쿼리하면 무한 재귀 오류가 납니다.
-- 관리자 여부만 SECURITY DEFINER 함수로 조회합니다.
create or replace function public.is_staff_admin(check_uid uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.staff_roles sr
    where sr.user_id = check_uid
      and sr.role = 'admin'
  );
$$;

grant execute on function public.is_staff_admin(uuid) to authenticated;

-- 관리자·운영자 공통 (예약 상태 변경 등)
create or replace function public.is_staff_user(check_uid uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.staff_roles sr
    where sr.user_id = check_uid
      and sr.role in ('admin', 'operator')
  );
$$;

grant execute on function public.is_staff_user(uuid) to authenticated;

-- 직원만 예약 행의 status 등 수정 가능
drop policy if exists "staff_update_reservation_requests" on public.reservation_requests;
create policy "staff_update_reservation_requests"
  on public.reservation_requests
  for update
  to authenticated
  using (public.is_staff_user(auth.uid()))
  with check (public.is_staff_user(auth.uid()));

-- 본인 행 조회 (역할 확인용)
drop policy if exists "staff_select_own" on public.staff_roles;
create policy "staff_select_own"
  on public.staff_roles
  for select
  to authenticated
  using (user_id = auth.uid());

-- 관리자는 전체 직원 목록 조회 (표시용)
drop policy if exists "staff_select_all_if_admin" on public.staff_roles;
create policy "staff_select_all_if_admin"
  on public.staff_roles
  for select
  to authenticated
  using (public.is_staff_admin(auth.uid()));

-- [필수] 기존에 만든 첫 관리자 계정을 아래에 연결하세요. Authentication → Users에서 해당 사용자 UUID 복사.
-- insert into public.staff_roles (user_id, role)
-- values ('여기에-관리자-UUID', 'admin')
-- on conflict (user_id) do update set role = excluded.role;

-- 팀원 등록은 Supabase Edge Function staff-invite(서비스 롤)에서만 staff_roles에 insert 합니다.
-- 로컬 배포: supabase/functions/staff-invite/index.ts 참고.

-- ========== 오마카세 코스 메뉴 (index.html 노출 · admin.html 관리) ==========
create table if not exists public.course_menu_items (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  sort_order int not null default 0,
  title_ko text not null,
  title_en text,
  description text not null,
  image_url text not null,
  image_alt text not null,
  is_active boolean not null default true
);

create index if not exists course_menu_items_sort_idx on public.course_menu_items (sort_order, id);

alter table public.course_menu_items enable row level security;

drop policy if exists "course_menu_anon_select_active" on public.course_menu_items;
create policy "course_menu_anon_select_active"
  on public.course_menu_items
  for select
  to anon
  using (is_active = true);

drop policy if exists "course_menu_auth_select_active" on public.course_menu_items;
create policy "course_menu_auth_select_active"
  on public.course_menu_items
  for select
  to authenticated
  using (is_active = true);

drop policy if exists "course_menu_admin_select_all" on public.course_menu_items;
create policy "course_menu_admin_select_all"
  on public.course_menu_items
  for select
  to authenticated
  using (public.is_staff_admin(auth.uid()));

drop policy if exists "course_menu_admin_insert" on public.course_menu_items;
create policy "course_menu_admin_insert"
  on public.course_menu_items
  for insert
  to authenticated
  with check (public.is_staff_admin(auth.uid()));

drop policy if exists "course_menu_admin_update" on public.course_menu_items;
create policy "course_menu_admin_update"
  on public.course_menu_items
  for update
  to authenticated
  using (public.is_staff_admin(auth.uid()))
  with check (public.is_staff_admin(auth.uid()));

drop policy if exists "course_menu_admin_delete" on public.course_menu_items;
create policy "course_menu_admin_delete"
  on public.course_menu_items
  for delete
  to authenticated
  using (public.is_staff_admin(auth.uid()));

-- 초기 메뉴(테이블이 비어 있을 때만 삽입)
insert into public.course_menu_items (sort_order, title_ko, title_en, description, image_url, image_alt, is_active)
select v.sort_order, v.title_ko, v.title_en, v.description, v.image_url, v.image_alt, v.is_active
from (
  values
    (1, '연어 니기리', 'Salmon Nigiri'::text,
     '제철 연어를 두껍게 올린 니기리. 윤이 도는 주황빛 살과 하얀 지방줄, 작은 허브 가니시가 어우러진 한 입입니다.'::text,
     'sushi1.png'::text, '연어 니기리 두 관과 생강 초절임'::text, true),
    (2, '가쓰오 니기리', 'Katsuo Nigiri',
     '겉만 은은하게 구워 속은 선명한 붉기를 살린 가다랑어 니기리. 생강을 얹어 잡내를 잡고 향을 돋웁니다.',
     'sushi2.png', '겉을 살짝 구운 참다랑어 니기리 두 관', true),
    (3, '북방조개 니기리', 'Hokkigai Nigiri',
     '제철 북방조개(호키가이)를 얹은 니기리. 흰 살에서 붉게 익은 끝까지 달큼한 육즙과 탄력 있는 식감이 살아 있습니다.',
     'sushi3.png', '북방조개 호키가이 니기리 두 관', true),
    (4, '제철 흰살 니기리', 'Shiromi Nigiri',
     '그날 들어온 흰살 생선에 껍질을 살린 채 가늘게 칼집을 내고, 골든 소스와 잎 채소로 향을 얹은 니기리입니다.',
     'sushi4.png', '껍질을 살린 제철 흰살 니기리 두 관', true),
    (5, '적채 니기리', 'Akami Nigiri',
     '깊은 붉은빛의 참다랑어 적채를 샤리 위에 얹었습니다. 소량의 겨자·허브 가니시와 가벼운 소금으로 풍미를 다듬습니다.',
     'sushi5.png', '적채 참다랑어 니기리 두 관', true),
    (6, '구이 니기리', 'Seared Nigiri',
     '표면만 살짝 구워 감칠맛을 살린 셰프 추천 네타. 허브와 와사비로 마무리한 니기리로 코스의 한 장면을 담았습니다.',
     'sushi6.png', '표면을 은은하게 구운 셰프 추천 니기리 두 관', true)
) as v(sort_order, title_ko, title_en, description, image_url, image_alt, is_active)
where not exists (select 1 from public.course_menu_items limit 1);

-- ---------------------------------------------------------------------------
-- (선택) 예약 상태·직원 UPDATE 정책만 기존 DB에 추가할 때:
-- 위 파일 전체 대신, 이미 staff_roles·is_staff_admin까지 적용된 경우
-- 「예약 처리 상태」 alter 블록 + is_staff_user 함수 + staff_update 정책만
-- 순서대로 SQL Editor에서 실행하면 됩니다.
-- ---------------------------------------------------------------------------

-- ========== Storage: 메뉴 이미지 업로드 (admin.html 파일 업로드 → public URL) ==========
-- Dashboard → Storage에서 동일 이름 버킷을 만들어도 되고, 아래를 SQL Editor에서 한 번 실행해도 됩니다.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'course-menu-images',
  'course-menu-images',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/svg+xml']::text[]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "course_menu_images_public_select" on storage.objects;
create policy "course_menu_images_public_select"
  on storage.objects
  for select
  using (bucket_id = 'course-menu-images');

drop policy if exists "course_menu_images_admin_insert" on storage.objects;
create policy "course_menu_images_admin_insert"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'course-menu-images'
    and public.is_staff_admin(auth.uid())
  );

drop policy if exists "course_menu_images_admin_update" on storage.objects;
create policy "course_menu_images_admin_update"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'course-menu-images'
    and public.is_staff_admin(auth.uid())
  )
  with check (
    bucket_id = 'course-menu-images'
    and public.is_staff_admin(auth.uid())
  );

drop policy if exists "course_menu_images_admin_delete" on storage.objects;
create policy "course_menu_images_admin_delete"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'course-menu-images'
    and public.is_staff_admin(auth.uid())
  );
