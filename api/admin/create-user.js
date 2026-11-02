import { createClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.VITE_SUPABASE_URL;
const publicKey = process.env.VITE_SUPABASE_ANON_KEY;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

export default async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });
  if (!supabaseUrl || !publicKey || !serviceKey) return res.status(503).json({ error: 'User creation is not configured. Set SUPABASE_SERVICE_ROLE_KEY in Vercel.' });
  const authorization = req.headers.authorization || '';
  const token = authorization.startsWith('Bearer ') ? authorization.slice(7) : '';
  if (!token) return res.status(401).json({ error: 'Sign in required' });
  const client = createClient(supabaseUrl, publicKey, { auth: { persistSession: false } });
  const { data: auth, error: authError } = await client.auth.getUser(token);
  if (authError || !auth.user) return res.status(401).json({ error: 'Invalid session' });
  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: role, error: roleError } = await admin.from('platform_admins').select('user_id').eq('user_id', auth.user.id).maybeSingle();
  if (roleError || !role) return res.status(403).json({ error: 'Super Admin only' });
  const { email, password, storeId, role: storeRole } = req.body || {};
  if (typeof email !== 'string' || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254 || typeof password !== 'string' || password.length < 12 || password.length > 128) return res.status(400).json({ error: 'Valid email and password of 12–128 characters required' });
  if (storeId && (!/^[0-9a-f-]{36}$/i.test(storeId) || !['owner','manager','cashier'].includes(storeRole))) return res.status(400).json({ error: 'Invalid store or role' });
  if (storeId) {
    const { data: store } = await admin.from('stores').select('id').eq('id',storeId).eq('active',true).maybeSingle();
    if (!store) return res.status(400).json({ error: 'Store not found or inactive' });
  }
  const { data, error } = await admin.auth.admin.createUser({ email: email.trim().toLowerCase(), password, email_confirm: true });
  if (error) return res.status(400).json({ error: error.message });
  if (storeId) {
    const { error: membershipError } = await admin.from('store_members').insert({ store_id: storeId, user_id: data.user.id, role: storeRole });
    if (membershipError) {
      await admin.auth.admin.deleteUser(data.user.id);
      return res.status(500).json({ error: 'Could not assign store; user creation rolled back' });
    }
  }
  return res.status(201).json({ id: data.user.id, email: data.user.email });
}
