/**
 * URL 缩短器业务函数（Node.js）
 * 路由（由 APIG 触发）：
 *   GET    /{linkId}      -> 301 重定向
 *   GET    /app           -> 列出短链（JSON 数组）
 *   POST   /app           -> 创建短链
 *   PUT    /app/{linkId}  -> 更新短链目标
 *   DELETE /app/{linkId}  -> 删除短链
 * 存储：OBS 对象（key=links/{id}，内容=目标 URL）
 * 凭据：函数委托的临时凭据由运行时注入 handler 的 context 参数
 */
const crypto = require('crypto');
const ObsClient = require('esdk-obs-nodejs');

const BASE62 = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
const MAX_LIST = 50; // 单次列举返回的最大条数

function shortCode(len = 6) {
  let s = '';
  for (let i = 0; i < len; i++) s += BASE62[crypto.randomInt(0, BASE62.length)];
  return s;
}
function json(status, body) {
  return { statusCode: status, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }, body: JSON.stringify(body) };
}
function bad(msg) { return json(400, { error: msg }); }
function redirect(loc) {
  return { statusCode: 301, headers: { Location: loc, 'Cache-Control': 'no-cache, no-store', 'Access-Control-Allow-Origin': '*' }, body: '' };
}
function obsError(r) {
  const st = r.CommonMsg && (r.CommonMsg.Status || r.CommonMsg.status);
  const msg = (r.CommonMsg && (r.CommonMsg.message || r.CommonMsg.error_message)) || '';
  return { status: st, message: msg };
}

exports.handler = async (event, context) => {
  // 同步调用会把请求体包装在 event.body；APIG 触发则为顶层事件。统一解包。
  let ev = event || {};
  if (typeof ev === 'object' && 'body' in ev && Object.keys(ev).length === 1) {
    ev = typeof ev.body === 'string' ? JSON.parse(ev.body) : ev.body;
  }
  const method = (ev.httpMethod || (ev.requestContext && ev.requestContext.httpMethod) || 'UNKNOWN').toUpperCase();
  const pathParams = ev.pathParameters || {};
  const bucket = process.env.OBS_BUCKET;
  const endpoint = process.env.OBS_ENDPOINT || ('https://obs.' + (process.env.REGION || 'cn-north-4') + '.myhuaweicloud.com');

  const client = new ObsClient({
    access_key_id: (context.securityAccessKey || context.accessKey) || '',
    secret_access_key: (context.securitySecretKey || context.secretKey) || '',
    server: endpoint,
    security_token: context.securityToken || '',
  });
  // ObsClient 构造为异步初始化（signatureContext 延迟设置），等待其就绪后使用
  await new Promise((r) => setTimeout(r, 500));

  try {
    // 1) 重定向
    if (method === 'GET' && pathParams.linkId) {
      const r = await client.getObject({ Bucket: bucket, Key: `links/${pathParams.linkId}` });
      const st = r.CommonMsg && (r.CommonMsg.Status || r.CommonMsg.status);
      if (!r.CommonMsg || st >= 300) return json(404, { error: 'not found' });
      const content = r.InterfaceResult && (r.InterfaceResult.Content || r.InterfaceResult.content);
      return redirect(String(content || '').trim());
    }
    // 2) 列表（GET /app）
    if (method === 'GET') {
      const r = await client.listObjects({ Bucket: bucket, Prefix: 'links/', MaxKeys: MAX_LIST });
      const st = r.CommonMsg && (r.CommonMsg.Status || r.CommonMsg.status);
      if (!r.CommonMsg || st >= 300) {
        const e = obsError(r);
        return json(502, { error: 'list failed ' + e.status + ' / ' + e.message });
      }
      const contents = ((r.InterfaceResult && (r.InterfaceResult.Contents || r.InterfaceResult.contents)) || []);
      const links = await Promise.all(contents.map(async (o) => {
        const key = o.Key || o.key || '';
        const id = key.replace('links/', '');
        let url = '';
        let lastModified = o.LastModified || o.lastModified || '';
        try {
          const g = await client.getObject({ Bucket: bucket, Key: key });
          const gst = g.CommonMsg && (g.CommonMsg.Status || g.CommonMsg.status);
          if (g.CommonMsg && gst < 300) {
            url = String((g.InterfaceResult && (g.InterfaceResult.Content || g.InterfaceResult.content)) || '').trim();
          }
        } catch (e) { /* 单条读取失败不影响整体列表 */ }
        return { id, url, owner: 'public', timestamp: lastModified };
      }));
      return json(200, links);
    }
    // 3) 创建（POST /app）
    if (method === 'POST') {
      let body = {};
      try { body = typeof ev.body === 'string' ? JSON.parse(ev.body) : (ev.body || {}); } catch (e) { /* ignore */ }
      const url = (body.url || '').trim();
      if (!/^https?:\/\/[^\s]+$/i.test(url)) return bad('invalid url');
      // 短码冲突时重试，避免覆盖已有短链
      for (let attempt = 0; attempt < 5; attempt++) {
        const id = shortCode();
        const exists = await client.getObject({ Bucket: bucket, Key: `links/${id}` });
        const est = exists.CommonMsg && (exists.CommonMsg.Status || exists.CommonMsg.status);
        if (exists.CommonMsg && est < 300) continue; // 已存在，换一个短码
        await client.putObject({ Bucket: bucket, Key: `links/${id}`, Body: url, ContentType: 'text/plain' });
        return json(201, { id, url, owner: 'public', timestamp: new Date().toISOString() });
      }
      return json(409, { error: 'failed to allocate a unique short code, please retry' });
    }
    // 4) 更新（PUT /app/{linkId}）
    if (method === 'PUT' && pathParams.linkId) {
      let body = {};
      try { body = typeof ev.body === 'string' ? JSON.parse(ev.body) : (ev.body || {}); } catch (e) { /* ignore */ }
      const url = (body.url || '').trim();
      if (!/^https?:\/\/[^\s]+$/i.test(url)) return bad('invalid url');
      await client.putObject({ Bucket: bucket, Key: `links/${pathParams.linkId}`, Body: url, ContentType: 'text/plain' });
      return json(200, { id: pathParams.linkId, url, owner: 'public', timestamp: new Date().toISOString() });
    }
    // 5) 删除（DELETE /app/{linkId}）
    if (method === 'DELETE' && pathParams.linkId) {
      await client.deleteObject({ Bucket: bucket, Key: `links/${pathParams.linkId}` });
      return json(200, { id: pathParams.linkId, deleted: true });
    }
    return bad('unsupported');
  } catch (e) {
    console.error('handler error:', e && e.message, e && e.stack);
    return json(500, { error: String((e && e.message) || e) });
  }
};
