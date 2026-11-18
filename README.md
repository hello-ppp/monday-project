# Monday Project · Photo Archive

뭔데?이 프로젝트(2026.11.14 – 11.16, 후암동) 참여자들이 직접 찍은 사진을 함께 올리고 보는 사진첩.

- 화면: GitHub Pages (`index.html`, `img/`)
- 사진·목록 저장: Supabase (`config.js`의 주소·공개 키, 설정은 `supabase/setup.sql`)
- 기획 · 디자인 [@llittlezoe](https://www.instagram.com/llittlezoe/)

## 관리자 비밀번호 바꾸기
Supabase 대시보드 > SQL Editor 에서 아래 한 줄의 `새비밀번호`만 바꿔 실행:

```sql
update public.settings set v = encode(extensions.digest('새비밀번호','sha256'),'hex') where k = 'admin_hash';
```
