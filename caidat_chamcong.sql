-- =====================================================================
-- PHẦN MỀM CHẤM CÔNG - BAN TUYÊN GIÁO TỈNH ỦY TUYÊN QUANG
-- File cài đặt CSDL. Chạy 1 lần trong SQL Editor của project Supabase.
-- Mọi bảng đều có tiền tố cc_ , không đụng tới các bảng sẵn có.
-- Chạy lại nhiều lần cũng không mất dữ liệu (dùng IF NOT EXISTS / ON CONFLICT).
-- =====================================================================

-- ---------- 1. BẢNG ----------
create table if not exists public.cc_nguoi_dung (
  email      text primary key,
  ho_ten     text,
  vai_tro    text not null default 'cham_cong'
             check (vai_tro in ('quan_tri','cham_cong')),
  created_at timestamptz not null default now()
);

create table if not exists public.cc_can_bo (
  id            bigserial primary key,
  stt           int  not null default 999,
  ho_ten        text not null,
  chuc_vu       text,
  dang_lam_viec boolean not null default true,
  created_at    timestamptz not null default now()
);

create table if not exists public.cc_cham_cong (
  can_bo_id         bigint not null references public.cc_can_bo(id) on delete cascade,
  ngay              date   not null,
  ky_hieu           text check (ky_hieu is null or ky_hieu in
                    ('+','CT','P','H','NB','Ô','Cô','TS','T','No','N','LĐ')),
  gio_them          numeric(4,1) not null default 0 check (gio_them between 0 and 24),
  gio_dem           numeric(4,1) not null default 0 check (gio_dem  between 0 and 24),
  noi_cong_tac      text,
  noi_dung_cong_tac text,
  cap_nhat_luc      timestamptz not null default now(),
  cap_nhat_boi      text,
  primary key (can_bo_id, ngay)
);
create index if not exists cc_cham_cong_ngay_idx on public.cc_cham_cong(ngay);

-- Ngày lễ/Tết thêm tay, nghỉ hoán đổi, đi làm bù.
-- (Các ngày lễ cố định 1/1, 30/4, 1/5, 2/9, 24/11 đã có sẵn trong phần mềm.)
create table if not exists public.cc_ngay_le (
  ngay date primary key,
  ten  text not null,
  loai text not null default 'le' check (loai in ('le','nghi_bu','lam_bu'))
);

create table if not exists public.cc_cai_dat (
  khoa    text primary key,
  gia_tri text
);

-- ---------- 2. TỰ GHI AI SỬA, SỬA LÚC NÀO ----------
create or replace function public.cc_ghi_nguoi_sua()
returns trigger language plpgsql as $$
begin
  new.cap_nhat_luc := now();
  new.cap_nhat_boi := coalesce(auth.jwt()->>'email', current_user);
  return new;
end $$;

drop trigger if exists cc_cham_cong_nguoi_sua on public.cc_cham_cong;
create trigger cc_cham_cong_nguoi_sua
  before insert or update on public.cc_cham_cong
  for each row execute function public.cc_ghi_nguoi_sua();

-- ---------- 3. PHÂN QUYỀN (RLS) ----------
-- Trả về vai trò của người đang đăng nhập; NULL nếu không có trong cc_nguoi_dung.
create or replace function public.cc_vai_tro()
returns text language sql stable security definer set search_path = public as $$
  select vai_tro from public.cc_nguoi_dung
  where lower(email) = lower(coalesce(auth.jwt()->>'email',''))
$$;
revoke all on function public.cc_vai_tro() from public, anon;
grant execute on function public.cc_vai_tro() to authenticated;

alter table public.cc_nguoi_dung enable row level security;
alter table public.cc_can_bo     enable row level security;
alter table public.cc_cham_cong  enable row level security;
alter table public.cc_ngay_le    enable row level security;
alter table public.cc_cai_dat    enable row level security;

-- Khóa hẳn với khách vãng lai (anon key trên trang công khai nuôi gà)
revoke all on public.cc_nguoi_dung, public.cc_can_bo, public.cc_cham_cong,
              public.cc_ngay_le, public.cc_cai_dat from anon;
grant select, insert, update, delete on public.cc_nguoi_dung, public.cc_can_bo,
              public.cc_cham_cong, public.cc_ngay_le, public.cc_cai_dat to authenticated;
grant usage, select on sequence public.cc_can_bo_id_seq to authenticated;

-- cc_nguoi_dung: ai cũng xem được dòng của mình; quản trị xem/sửa tất cả
drop policy if exists cc_nd_xem on public.cc_nguoi_dung;
create policy cc_nd_xem on public.cc_nguoi_dung for select to authenticated
  using (lower(email) = lower(auth.jwt()->>'email') or public.cc_vai_tro() = 'quan_tri');
drop policy if exists cc_nd_sua on public.cc_nguoi_dung;
create policy cc_nd_sua on public.cc_nguoi_dung for all to authenticated
  using (public.cc_vai_tro() = 'quan_tri') with check (public.cc_vai_tro() = 'quan_tri');

-- cc_can_bo: người được cấp quyền thì xem; chỉ quản trị sửa
drop policy if exists cc_cb_xem on public.cc_can_bo;
create policy cc_cb_xem on public.cc_can_bo for select to authenticated
  using (public.cc_vai_tro() is not null);
drop policy if exists cc_cb_sua on public.cc_can_bo;
create policy cc_cb_sua on public.cc_can_bo for all to authenticated
  using (public.cc_vai_tro() = 'quan_tri') with check (public.cc_vai_tro() = 'quan_tri');

-- cc_cham_cong, cc_ngay_le: người được cấp quyền xem và chấm
drop policy if exists cc_cc_tat_ca on public.cc_cham_cong;
create policy cc_cc_tat_ca on public.cc_cham_cong for all to authenticated
  using (public.cc_vai_tro() is not null) with check (public.cc_vai_tro() is not null);
drop policy if exists cc_le_tat_ca on public.cc_ngay_le;
create policy cc_le_tat_ca on public.cc_ngay_le for all to authenticated
  using (public.cc_vai_tro() is not null) with check (public.cc_vai_tro() is not null);

-- cc_cai_dat: người được cấp quyền xem; chỉ quản trị sửa
drop policy if exists cc_cd_xem on public.cc_cai_dat;
create policy cc_cd_xem on public.cc_cai_dat for select to authenticated
  using (public.cc_vai_tro() is not null);
drop policy if exists cc_cd_sua on public.cc_cai_dat;
create policy cc_cd_sua on public.cc_cai_dat for all to authenticated
  using (public.cc_vai_tro() = 'quan_tri') with check (public.cc_vai_tro() = 'quan_tri');

-- ---------- 4. DỮ LIỆU BAN ĐẦU ----------
-- 4a. Tài khoản được dùng phần mềm.
--     SỬA 2 EMAIL DƯỚI ĐÂY trước khi chạy (đúng email đã tạo ở Authentication > Users).
insert into public.cc_nguoi_dung (email, ho_ten, vai_tro) values
  ('ngacvantuan.hg@gmail.com',   'Ngạc Văn Tuấn',          'quan_tri'),
  ('nguyetquehg@gmail.com', 'Nguyễn Thị Bích Nguyệt', 'cham_cong')
on conflict (email) do nothing;

-- 4b. Thông tin in trên bảng chấm công
insert into public.cc_cai_dat (khoa, gia_tri) values
  ('ten_don_vi',      'Ban Tuyên giáo Tỉnh ủy'),
  ('bo_phan',         'Văn phòng Ban'),
  ('ma_qhns',         '1087976'),
  ('dia_danh',        'Tuyên Quang'),
  ('nguoi_cham_cong', 'Nguyễn Thị Bích Nguyệt'),
  ('ten_phu_trach',   ''),
  ('ten_xac_nhan',    ''),
  ('ten_thu_truong',  '')
on conflict (khoa) do nothing;

-- 4c. Danh sách 46 cán bộ theo bảng nâng lương ngày 01/10/2026 (chỉ nạp khi bảng còn trống)
insert into public.cc_can_bo (stt, ho_ten, chuc_vu)
select * from (values
  (1, 'Trần Mạnh Lợi', 'Trưởng Ban'),
  (2, 'Nguyễn Lam Sơn', 'Phó Trưởng Ban Thường trực'),
  (3, 'Lê Mạnh Cường', 'Phó Trưởng Ban'),
  (4, 'Nguyễn Văn Hưng', 'Phó Trưởng Ban'),
  (5, 'Đặng Ái Xoan', 'Phó Trưởng Ban'),
  (6, 'Hoàng Thị Hằng', 'Phó Trưởng Ban'),
  (7, 'Chẩu Thị Thu', 'Phó Trưởng Ban'),
  (8, 'Đinh Thị Thúy', 'Chánh Văn Phòng'),
  (9, 'Lê Minh Tiến', 'Phó Chánh VP'),
  (10, 'Phạm Thị Kim Anh', 'Phó Chánh VP'),
  (11, 'Ngạc Văn Tuấn', 'Chuyên viên VP'),
  (12, 'Phạm Thị Nga', 'Chuyên viên VP'),
  (13, 'Trần Thị Thảo', 'Chuyên viên VP'),
  (14, 'Nguyễn Thị Phương Thảo', 'Chuyên viên VP'),
  (15, 'Vũ Thị Thúy Hằng', 'Chuyên viên VP'),
  (16, 'Nguyễn Thị Bích Nguyệt', 'Kế toán'),
  (17, 'Lương Hồng Thái', 'Kế toán'),
  (18, 'Triệu Thị Thanh', 'Văn thư'),
  (19, 'Mai Thị Trịnh', 'Văn thư'),
  (20, 'Nguyễn Văn Thành', 'Lái xe'),
  (21, 'Hoàng Văn Hạnh', 'Lái xe'),
  (22, 'Nguyễn Văn Thắng', 'Lái xe'),
  (23, 'Nguyễn Hoàng Minh', 'Lái xe'),
  (24, 'Nguyễn Thị Ngoan', 'Tạp vụ'),
  (25, 'Nguyễn Thu Vân', 'Trưởng phòng TT, BC-XB'),
  (26, 'Hoàng Quân', 'Phó Trưởng Phòng TT, BC-XB'),
  (27, 'Nguyễn Viết An', 'Phó Trưởng phòng Tuyên truyền, Báo chí - Xuất bản'),
  (28, 'Lê Hồng Hải', 'Chuyên viên Phòng TT, BC-XB'),
  (29, 'Hoàng Thị Thu Hằng', 'Chuyên viên Phòng TT, BC-XB'),
  (30, 'Dương Hồng Thắm', 'Chuyên viên Phòng TT, BC-XB'),
  (31, 'Chẩu Yến Chi', 'Chuyên viên Phòng TT, BC-XB'),
  (32, 'Hoàng Thị Thu Trang', 'Chuyên viên Phòng TT, BC-XB'),
  (33, 'Nguyễn Thanh Thủy', 'Chuyên viên Phòng TT, BC-XB'),
  (34, 'Vũ Trung Kiên', 'Trưởng phòng LLCT, LSĐ'),
  (35, 'Nguyễn Văn Đức', 'Phó Trưởng phòng LLCT, LSĐ'),
  (36, 'Nguyễn Thị Yến', 'Chuyên viên Phòng LLCT, LSĐ'),
  (37, 'Lê Thị Thu Nga', 'Chuyên viên Phòng LLCT, LSĐ'),
  (38, 'Lê Thanh Quỳnh', 'Chuyên viên Phòng LLCT, LSĐ'),
  (39, 'Đào Hồng Xiêm', 'Chuyên viên Phòng LLCT, LSĐ'),
  (40, 'Lê Kim Anh', 'Chuyên viên Phòng LLCT, LSĐ'),
  (41, 'Phan Thanh Bình', 'Trưởng Phòng KG, VH-VN'),
  (42, 'Nguyễn Thị Mai Lan', 'Phó Trưởng Phòng KG, VH-VN'),
  (43, 'Lương Hoàng Nghĩa', 'Phó Trưởng Phòng KG, VH-VN'),
  (44, 'Trần Thị Minh Ngọc', 'Chuyên viên Phòng KG, VH-VN'),
  (45, 'Đỗ Thu Hiền', 'Chuyên viên Phòng KG, VH-VN'),
  (46, 'Trần Thị Thu Phương', 'Chuyên viên Phòng KG, VH-VN')
) as v(stt, ho_ten, chuc_vu)
where not exists (select 1 from public.cc_can_bo);

-- Kiểm tra nhanh
select (select count(*) from public.cc_can_bo)    as so_can_bo,
       (select count(*) from public.cc_nguoi_dung) as so_tai_khoan;
