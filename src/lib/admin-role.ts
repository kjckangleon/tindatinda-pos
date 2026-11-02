export function resolveAdminRole(rpcRole: boolean | null, apiRole: boolean | null) {
  // A negative server lookup must not override an authenticated positive RPC.
  return rpcRole === true || apiRole === true;
}
export function isExpectedNonAdmin(rpcRole: boolean | null, apiCode: string | null) {
  return rpcRole === false && (apiCode === 'NO_MATCHING_ROLE' || apiCode === null);
}
