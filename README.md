# 스시 카이덴 — 웹사이트

프리미엄 오마카세 레스토랑 **스시 카이덴** 소개·예약 신청용 정적 웹사이트입니다.

## 구성

| 파일 | 설명 |
|------|------|
| `index.html` | 메인 퍼블릭 페이지 |
| `admin.html` | 예약·메뉴·팀 관리( Supabase Auth 필요 ) |
| `admin-signup.html` | 관리자 계정 관련 진입 |
| `master.html` | UI 마스터(배너 카드 등 디자인 기준) |
| `test.html` | UI 컴포넌트 테스트용 |
| `supabase-setup.sql` | DB·RLS·Storage 정책 초기 설정(SQL Editor에서 실행) |
| `supabase/functions/staff-invite/` | 팀원 초대용 Edge Function |

## 기술 스택

- HTML / 바닐라 JavaScript(모듈)
- [Tailwind CSS](https://tailwindcss.com/)(CDN)
- [Phosphor Icons](https://phosphoricons.com/), [Swiper](https://swiperjs.com/)
- Google Fonts: Hahmlet, Moon Dance
- 백엔드: [Supabase](https://supabase.com/)(Auth, DB, Storage, Edge Functions)

## 로컬에서 보기

빌드 도구 없이 브라우저로 열어도 동작합니다.

```bash
# 예: Python 내장 서버 (선택)
python -m http.server 8080
```

브라우저에서 `http://localhost:8080/index.html` 로 접속합니다.

## Supabase 연동

1. Supabase 프로젝트를 만든 뒤, **`supabase-setup.sql`** 내용을 SQL Editor에서 실행합니다.
2. 웹 클라이언트용 URL·**anon 키**는 `index.html`, `admin.html`, `admin-signup.html` 의 Supabase 초기화 부분에 맞춰 **본인 프로젝트 값으로 교체**해야 합니다.
3. 팀원 초대 기능을 쓰려면 `supabase/functions/staff-invite` 를 배포하고, 대시보드에서 서비스 롤 등 환경 변수가 주입되는지 확인합니다. 자세한 점은 해당 폴더의 `index.ts` 주석을 참고하세요.

> **주의:** `service_role` 키는 클라이언트 HTML에 넣지 마세요. Git에는 `.env` 등 비밀 파일을 올리지 않도록 `.gitignore` 로 제외해 두었습니다.

## 파비콘

- `favicon_32x32.png`, `favicon_180x180.png` — HTML `<head>` 에 연결되어 있습니다.

## 라이선스

저장소 소유자의 정책에 따릅니다. 상업적 이용·이미지·폰트 라이선스는 별도 확인이 필요할 수 있습니다.
