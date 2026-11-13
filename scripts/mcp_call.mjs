#!/usr/bin/env node
// 通过 stdio JSON-RPC 调用 harmonyos-mcp 工具（同一会话内可多次调用）
// 用法: node mcp_call.mjs '[["tool1",{...}],["tool2",{...}]]' [--timeout ms]
import { spawn } from 'child_process';

const calls = JSON.parse(process.argv[2]);
const timeoutIdx = process.argv.indexOf('--timeout');
const timeout = timeoutIdx > 0 ? parseInt(process.argv[timeoutIdx + 1]) : 300000;

const p = spawn('/opt/homebrew/bin/harmonyos-mcp', [], {
  stdio: ['pipe', 'pipe', 'inherit'],
  // PackageHap 需要 Java：补 DevEco 自带 JBR，否则报「Unable to locate a Java Runtime」
  env: {
    ...process.env,
    DEVECO_SDK_HOME: '/Applications/DevEco-Studio.app/Contents/sdk',
    JAVA_HOME: '/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home'
  }
});
let buf = '';
const send = (m) => p.stdin.write(JSON.stringify(m) + '\n');
let nextId = 1;
let pending = 0;
const results = [];
let failed = false;

function issueCalls() {
  for (const [name, args] of calls) {
    const id = nextId++;
    pending++;
    send({ jsonrpc: '2.0', id, method: 'tools/call', params: { name, arguments: args ?? {} } });
  }
}

p.stdout.on('data', (d) => {
  buf += d.toString();
  let idx;
  while ((idx = buf.indexOf('\n')) >= 0) {
    const line = buf.slice(0, idx); buf = buf.slice(idx + 1);
    if (!line.trim()) continue;
    let m; try { m = JSON.parse(line); } catch { continue; }
    if (m.id === 0) {
      send({ jsonrpc: '2.0', method: 'notifications/initialized' });
      issueCalls();
    } else if (m.id >= 1) {
      pending--;
      const c = m.result?.content;
      const text = c ? c.map(x => x.text ?? JSON.stringify(x)).join('\n') : JSON.stringify(m.result ?? m.error);
      results.push(text);
      if (m.error || m.result?.isError) failed = true;
      if (pending === 0) {
        results.forEach((t, i) => { console.log(`===== [${calls[i][0]}] =====`); console.log(t); });
        process.exit(failed ? 1 : 0);
      }
    }
  }
});
setTimeout(() => { console.error('TIMEOUT waiting for tool result'); process.exit(2); }, timeout);
send({ jsonrpc: '2.0', id: 0, method: 'initialize', params: { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'kimi', version: '0' } } });
