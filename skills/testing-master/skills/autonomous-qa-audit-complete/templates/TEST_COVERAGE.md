# Test Coverage — QA Audit

**Project:** {{PROJECT_NAME}}  
**Generated:** {{ISO_DATE}}  
**Discovery source:** `qa-audit/discovery.json`

---

## Coverage summary

| Metric | Value |
|--------|------:|
| Routes discovered | |
| Routes tested | |
| **Route coverage** | **{{}}%** |
| User flows discovered | |
| User flows tested | |
| **Flow coverage** | **{{}}%** |
| API endpoints discovered | |
| API endpoints tested | |
| **API coverage** | **{{}}%** |

---

## Route matrix

| Route | Auth | Desktop | Tablet | Mobile | Links | Buttons | Forms | Console | Status |
|-------|------|---------|--------|--------|-------|---------|-------|---------|--------|
| `/` | guest | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | |
| `/login` | guest | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | |
| `/dashboard` | user | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | |

**Legend:** ✅ pass · ❌ fail · ⬜ not run · ⏭ skip

---

## User flow matrix

| Flow ID | Description | Roles | Last run | Status |
|---------|-------------|-------|----------|--------|
| `auth-login` | Login → dashboard | guest | | |
| `auth-logout` | Logout → login | user | | |
| `auth-register` | Register → verify | guest | | |
| `auth-reset` | Password reset email | guest | | |
| `crud-{{entity}}` | Create read update delete | user | | |

---

## API matrix

| Method | Path | Auth | 2xx | 4xx validation | Error handling | Status |
|--------|------|------|-----|----------------|----------------|--------|
| GET | `/api/...` | | ⬜ | ⬜ | ⬜ | |

---

## CRUD entity coverage

| Entity | Create | Read | Update | Delete | DB verify |
|--------|--------|------|--------|--------|-----------|
| | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |

---

## Form coverage

| Page | Form | Empty | Invalid | Valid | Status |
|------|------|-------|---------|-------|--------|
| `/login` | login | ⬜ | ⬜ | ⬜ | |

---

## Role-based access

| Route / action | Guest | User | Admin |
|----------------|-------|------|-------|
| `/admin` | deny | deny | allow |

---

## Gaps (untested)

| Item | Reason | Priority to add |
|------|--------|-----------------|
| | | |

---

## Playwright specs map

| Spec file | Covers |
|-----------|--------|
| `scripts/qa-audit/crawl.spec.ts` | All routes crawl |
| `scripts/qa-audit/flows.auth.spec.ts` | Auth flows |
| `scripts/qa-audit/flows.crud.spec.ts` | CRUD per entity |
