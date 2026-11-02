import { describe, expect, it } from 'vitest';
import { isExpectedNonAdmin, resolveAdminRole } from '../src/lib/admin-role';
describe('admin role regression', () => {
  it('accepts a verified RPC role even when the API lookup fails', () => expect(resolveAdminRole(true, false)).toBe(true));
  it('accepts a verified API role', () => expect(resolveAdminRole(false, true)).toBe(true));
  it('does not grant admin to a regular registered user', () => expect(resolveAdminRole(false, false)).toBe(false));
  it('does not grant admin without verification', () => expect(resolveAdminRole(null, null)).toBe(false));
  it('treats ordinary non-admin results as expected', () => expect(isExpectedNonAdmin(false, 'NO_MATCHING_ROLE')).toBe(true));
  it('does not treat missing permission verification as ordinary non-admin', () => expect(isExpectedNonAdmin(null, 'ROLE_READ_FAILED')).toBe(false));
});
