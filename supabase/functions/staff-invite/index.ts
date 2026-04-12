/**
 * 관리자(admin)만 새 Auth 사용자 + staff_roles 행을 추가합니다.
 *
 * 호스팅 배포 시 SUPABASE_URL·SUPABASE_SERVICE_ROLE_KEY는 Supabase가 자동 주입합니다.
 *
 *   npx supabase login
 *   npx supabase link --project-ref <프로젝트 ref>
 *   npx supabase functions deploy staff-invite
 *
 * supabase/config.toml 에서 verify_jwt = false 이면 JWT 검증은 이 파일에서만 수행합니다.
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

var corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async function (req) {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  var supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  var serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

  if (!supabaseUrl || !serviceKey) {
    return new Response(
      JSON.stringify({ error: 'Server misconfigured (missing SUPABASE_URL or service role)' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  var authHeader = req.headers.get('Authorization') || '';
  if (!authHeader.startsWith('Bearer ')) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  var jwt = authHeader.slice(7);
  var adminClient = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  var userResult = await adminClient.auth.getUser(jwt);
  if (userResult.error || !userResult.data.user) {
    return new Response(JSON.stringify({ error: 'Invalid or expired session' }), {
      status: 401,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  var inviterId = userResult.data.user.id;

  var roleCheck = await adminClient
    .from('staff_roles')
    .select('role')
    .eq('user_id', inviterId)
    .eq('role', 'admin')
    .maybeSingle();

  if (roleCheck.error || !roleCheck.data) {
    return new Response(
      JSON.stringify({
        error:
          '관리자 권한이 없습니다. SQL로 staff_roles에 본인 user_id를 admin으로 등록했는지 확인하세요.',
      }),
      { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  var body: { email?: string; password?: string; role?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON body' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  var email = (body.email || '').trim().toLowerCase();
  var password = body.password || '';
  var newRole = body.role === 'admin' ? 'admin' : body.role === 'operator' ? 'operator' : '';

  if (!email || !password || !newRole) {
    return new Response(
      JSON.stringify({ error: 'email, password, role(admin|operator)가 필요합니다.' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  if (password.length < 6) {
    return new Response(JSON.stringify({ error: '비밀번호는 6자 이상이어야 합니다.' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  var createResult = await adminClient.auth.admin.createUser({
    email: email,
    password: password,
    email_confirm: true,
    user_metadata: { staff_role: newRole },
  });

  if (createResult.error) {
    return new Response(
      JSON.stringify({
        error: createResult.error.message || '사용자 생성에 실패했습니다.',
      }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  var newUserId = createResult.data.user?.id;
  if (!newUserId) {
    return new Response(JSON.stringify({ error: '사용자 ID를 받지 못했습니다.' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  var insertRole = await adminClient.from('staff_roles').insert({
    user_id: newUserId,
    role: newRole,
  });

  if (insertRole.error) {
    await adminClient.auth.admin.deleteUser(newUserId);
    return new Response(
      JSON.stringify({
        error: insertRole.error.message || '역할 저장에 실패했습니다.',
      }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  return new Response(
    JSON.stringify({
      ok: true,
      email: email,
      role: newRole,
    }),
    { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  );
});
