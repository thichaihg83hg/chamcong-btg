-- =====================================================================
-- CẬP NHẬT: THÊM PHẦN CÔNG TÁC PHÍ (bảng kê C17-HD)
-- Chạy 1 lần trong SQL Editor, SAU file caidat_chamcong.sql.
-- Chạy lại nhiều lần cũng không mất dữ liệu.
-- =====================================================================

-- 1. Cán bộ hưởng mức lãnh đạo (hệ số phụ cấp chức vụ từ 0,8 đến 1,2)
alter table public.cc_can_bo add column if not exists muc_lanh_dao boolean not null default false;
update public.cc_can_bo set muc_lanh_dao = true
 where ho_ten in ('Trần Mạnh Lợi', 'Nguyễn Lam Sơn');

-- 2. Mã QHNS và chữ ký bảng kê
update public.cc_cai_dat set gia_tri = '1134652' where khoa = 'ma_qhns';
insert into public.cc_cai_dat (khoa, gia_tri) values
  ('nguoi_lap_bieu', 'Nguyễn Thị Bích Nguyệt'),
  ('ke_toan_truong', 'Nguyễn Thị Bích Nguyệt')
on conflict (khoa) do nothing;

-- 3. Đợt công tác (thông tin thanh toán của một đoàn)
create table if not exists public.cc_dot_cong_tac (
  id             bigserial primary key,
  noi            text,
  noi_dung       text,
  tu_ngay        date not null,
  den_ngay       date not null,
  dia_ban        text not null default 'xa' check (dia_ban in ('tw','tinh','phuong','xa')),
  trong_ngay     boolean not null default false,
  khoang_cach_km numeric(7,1) not null default 0,
  xe_co_quan     boolean not null default false,
  can_cu         text,
  cap_nhat_luc   timestamptz not null default now()
);
create index if not exists cc_dot_ngay_idx on public.cc_dot_cong_tac(tu_ngay, den_ngay);

-- 4. Tiền của từng người trong đợt (NULL = phần mềm tự tính theo mức chi)
create table if not exists public.cc_dot_nguoi (
  dot_id            bigint not null references public.cc_dot_cong_tac(id) on delete cascade,
  can_bo_id         bigint not null references public.cc_can_bo(id) on delete cascade,
  luu_tru           numeric(14,0),
  hinh_thuc_phong   text check (hinh_thuc_phong is null or hinh_thuc_phong in ('khoan','hoa_don','khong')),
  so_dem            numeric(5,1),
  tien_phong        numeric(14,0),
  tien_ve           numeric(14,0) not null default 0,
  phuong_tien       text check (phuong_tien is null or phuong_tien in ('khong','km','xang','nhap')),
  so_km             numeric(8,1),
  don_gia_km        numeric(12,0),
  so_lit            numeric(8,2),
  gia_xang          numeric(12,0),
  tien_phuong_tien  numeric(14,0) not null default 0,
  tam_ung           numeric(14,0) not null default 0,
  primary key (dot_id, can_bo_id)
);

-- 5. Người hưởng khoán công tác phí theo tháng
create table if not exists public.cc_khoan_thang (
  thang       text   not null,               -- dạng 'YYYY-MM'
  can_bo_id   bigint not null references public.cc_can_bo(id) on delete cascade,
  so_ngay_an  int,                           -- NULL = tự đếm số ngày CT làm việc trong tháng
  primary key (thang, can_bo_id)
);

-- 6. Phân quyền: ai được cấp quyền chấm công thì xem và sửa được
alter table public.cc_dot_cong_tac enable row level security;
alter table public.cc_dot_nguoi    enable row level security;
alter table public.cc_khoan_thang  enable row level security;
revoke all on public.cc_dot_cong_tac, public.cc_dot_nguoi, public.cc_khoan_thang from anon;
grant select, insert, update, delete on public.cc_dot_cong_tac, public.cc_dot_nguoi, public.cc_khoan_thang to authenticated;
grant usage, select on sequence public.cc_dot_cong_tac_id_seq to authenticated;

drop policy if exists cc_dot_tat_ca on public.cc_dot_cong_tac;
create policy cc_dot_tat_ca on public.cc_dot_cong_tac for all to authenticated
  using (public.cc_vai_tro() is not null) with check (public.cc_vai_tro() is not null);
drop policy if exists cc_dn_tat_ca on public.cc_dot_nguoi;
create policy cc_dn_tat_ca on public.cc_dot_nguoi for all to authenticated
  using (public.cc_vai_tro() is not null) with check (public.cc_vai_tro() is not null);
drop policy if exists cc_kt_tat_ca on public.cc_khoan_thang;
create policy cc_kt_tat_ca on public.cc_khoan_thang for all to authenticated
  using (public.cc_vai_tro() is not null) with check (public.cc_vai_tro() is not null);

-- Kiểm tra nhanh: phải ra 2 người mức lãnh đạo và mã QHNS 1134652
select (select count(*) from public.cc_can_bo where muc_lanh_dao) as so_lanh_dao,
       (select gia_tri from public.cc_cai_dat where khoa = 'ma_qhns') as ma_qhns;
