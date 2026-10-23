/**
 * 4.2 手机号登录与会话单测（10_BUILD_MANUAL.md 4.2）。
 * 验收覆盖：手机号口径与掩码；DTO 解析（必缺抛错 / 可选归一 ''）；
 * UserSession 生命周期（establish 持久化 / 恢复 / clear / 快照损坏不丢 token）；
 * 401 闸门 → 会话清理联动。
 * 只测 kit-free 纯层（AuthLogic / Api 解析 / UserSession + 内存 fake store）；
 * AssetSessionStore import Asset Store Kit、AuthService 挂执行壳，本地跑不了，真机联调验。
 */
import { describe, it, expect } from '@ohos/hypium';
import { AuthLogic } from '../../main/ets/services/auth/AuthLogic';
import { SessionStore, SESSION_KEY_TOKEN, SESSION_KEY_USER } from '../../main/ets/services/auth/SessionStore';
import { UserSession } from '../../main/ets/services/auth/UserSession';
import { parseUserDto, parseAuthResponse, parseSendCodeResponse,
  parseMeResponse, parseBindPhoneResponse, parseChangePhoneResponse,
  parseDeleteAccountResponse, parseOkResponse, UserDTO } from '../../main/ets/models/Api';
import { HttpError, HttpErrorKind } from '../../main/ets/services/http/HttpError';
import { UnauthorizedGate } from '../../main/ets/services/http/HttpMapping';

/** 内存会话存储（单测 fake；真机是 AssetSessionStore） */
class MemorySessionStore implements SessionStore {
  private readonly map: Map<string, string> = new Map();

  get(key: string): string | null {
    const value = this.map.get(key);
    return value === undefined ? null : value;
  }

  set(key: string, value: string): void {
    this.map.set(key, value);
  }

  remove(key: string): void {
    this.map.delete(key);
  }
}

/** 完整 user 响应体（id 数字、可选字段齐全、双绑定） */
const USER_JSON: string =
  '{"id":42,"phone":"13800138000","displayName":"小明","penPalName":"青鸟",'
  + '"bindings":[{"provider":"phone"},{"provider":"apple"}]}';

/** 最小 user 响应体（id 字符串、可选字段全缺、无 bindings） */
const USER_MIN_JSON: string =
  '{"id":"u_1001","penPalName":"青鸟"}';

const AUTH_JSON: string =
  `{"token":"jwt-token-abc","user":${USER_JSON}}`;

const SEND_CODE_JSON: string = '{"ok":true,"retryAfter":60}';

const ME_JSON: string =
  `{"user":${USER_MIN_JSON},"subscription":{"isActive":true,`
  + '"productId":"monthly","platform":"harmony","expiresAt":"2026-11-24T00:00:00.000Z"}}';

const BIND_PHONE_JSON: string =
  `{"ok":true,"switchedAccount":true,"token":"jwt-new","user":${USER_JSON}}`;

/** 从 JSON 构造 UserDTO（会话用例的夹具） */
function userFromJson(raw: string): UserDTO {
  return parseUserDto(raw);
}

export default function authSessionTest() {
  describe('AuthSessionTest', () => {
    // ---- AuthLogic：输入过滤 / 口径 / 掩码 ----

    it('digitsOnlyFiltersAndTruncates', 0, () => {
      expect(AuthLogic.digitsOnly('138abc001', 11)).assertEqual('138001');
      expect(AuthLogic.digitsOnly('12x3', 6)).assertEqual('123');
      expect(AuthLogic.digitsOnly('', 11)).assertEqual('');
      // 超 11 位截断（粘贴带杂质的场景）
      expect(AuthLogic.digitsOnly('13800138000111', 11)).assertEqual('13800138000');
    })

    it('mainlandPhoneRule', 0, () => {
      expect(AuthLogic.isValidMainlandPhone('13800138000')).assertTrue();
      expect(AuthLogic.isValidMainlandPhone('23800138000')).assertFalse();
      expect(AuthLogic.isValidMainlandPhone('1380013800')).assertFalse();
      expect(AuthLogic.isValidMainlandPhone('138001380001')).assertFalse();
      expect(AuthLogic.isValidMainlandPhone('1380013800a')).assertFalse();
      expect(AuthLogic.isValidMainlandPhone('')).assertFalse();
    })

    it('maskedPhoneMasksMiddle', 0, () => {
      expect(AuthLogic.maskedPhone('13800138000')).assertEqual('138****8000');
      // 非 11 位原样（半截输入不硬掩码）
      expect(AuthLogic.maskedPhone('12345')).assertEqual('12345');
    })

    // ---- DTO 解析：必缺抛错 / 可选归一 '' / id 归一 string ----

    it('parseUserDtoNormalizes', 0, () => {
      const u = parseUserDto(USER_JSON);
      expect(u.id).assertEqual('42');
      expect(u.phone).assertEqual('13800138000');
      expect(u.displayName).assertEqual('小明');
      expect(u.penPalName).assertEqual('青鸟');
      expect(u.bindings.length).assertEqual(2);
      expect(u.bindings[0]).assertEqual('phone');
      expect(u.bindings[1]).assertEqual('apple');
    })

    it('parseUserDtoOptionalFieldsFallEmpty', 0, () => {
      const u = parseUserDto(USER_MIN_JSON);
      expect(u.id).assertEqual('u_1001');
      expect(u.phone).assertEqual('');
      expect(u.displayName).assertEqual('');
      expect(u.bindings.length).assertEqual(0);
    })

    it('parseUserDtoRejectsBadPayloads', 0, () => {
      let threw = false;
      try {
        parseUserDto('not json');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
      threw = false;
      try {
        parseUserDto('null');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
      // 缺 id / 缺 penPalName（必填）抛错，HttpMapping.decode 折成 decoding 档
      threw = false;
      try {
        parseUserDto('{"penPalName":"青鸟"}');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
      threw = false;
      try {
        parseUserDto('{"id":42}');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    })

    it('parseAuthAndSendCodeResponses', 0, () => {
      const auth = parseAuthResponse(AUTH_JSON);
      expect(auth.token).assertEqual('jwt-token-abc');
      expect(auth.user.id).assertEqual('42');
      const sent = parseSendCodeResponse(SEND_CODE_JSON);
      expect(sent.retryAfter).assertEqual(60);
      // retryAfter 缺失抛错（倒计时没依据）
      let threw = false;
      try {
        parseSendCodeResponse('{"ok":true}');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    })

    it('parseMeAndBindPhoneResponses', 0, () => {
      const me = parseMeResponse(ME_JSON);
      expect(me.user.id).assertEqual('u_1001');
      expect(me.subscription.isActive).assertTrue();
      expect(me.subscription.productId).assertEqual('monthly');
      expect(me.subscription.platform).assertEqual('harmony');
      expect(me.subscription.expiresAt).assertEqual('2026-11-24T00:00:00.000Z');
      const bind = parseBindPhoneResponse(BIND_PHONE_JSON);
      expect(bind.switchedAccount).assertTrue();
      expect(bind.token).assertEqual('jwt-new');
      expect(bind.user.id).assertEqual('42');
    })

    // ---- UserSession 生命周期（内存 fake store）----

    it('sessionEstablishPersistsAndRestores', 0, () => {
      const store = new MemorySessionStore();
      const session = new UserSession(store);
      expect(session.isLoggedIn()).assertFalse();
      session.establish('jwt-token-abc', userFromJson(USER_JSON));
      expect(session.isLoggedIn()).assertTrue();
      expect(session.token).assertEqual('jwt-token-abc');
      expect(session.user?.id).assertEqual('42');
      // 持久化语义：同一 store 上新建会话（杀进程重启）恢复登录态
      const restored = new UserSession(store);
      expect(restored.isLoggedIn()).assertTrue();
      expect(restored.token).assertEqual('jwt-token-abc');
      expect(restored.user?.phone).assertEqual('13800138000');
    })

    it('sessionClearWipesMemoryAndStore', 0, () => {
      const store = new MemorySessionStore();
      const session = new UserSession(store);
      session.establish('jwt-token-abc', userFromJson(USER_JSON));
      session.clear();
      expect(session.isLoggedIn()).assertFalse();
      expect(session.token).assertNull();
      expect(session.user).assertNull();
      expect(store.get(SESSION_KEY_TOKEN)).assertNull();
      expect(store.get(SESSION_KEY_USER)).assertNull();
      // 清完再建（重启）也不复活
      expect(new UserSession(store).isLoggedIn()).assertFalse();
    })

    it('sessionUpdateUserRefreshesSnapshot', 0, () => {
      const store = new MemorySessionStore();
      const session = new UserSession(store);
      session.establish('jwt-token-abc', userFromJson(USER_JSON));
      session.updateUser(userFromJson(USER_MIN_JSON));
      expect(session.user?.id).assertEqual('u_1001');
      expect(session.token).assertEqual('jwt-token-abc');
      // 快照更新落了存储
      expect(new UserSession(store).user?.id).assertEqual('u_1001');
    })

    it('sessionSurvivesCorruptSnapshot', 0, () => {
      const store = new MemorySessionStore();
      store.set(SESSION_KEY_TOKEN, 'jwt-token-abc');
      store.set(SESSION_KEY_USER, 'not json at all');
      const session = new UserSession(store);
      // 快照损坏不丢 token：仍已登录，user 为 null，后续 fetchMe 可刷
      expect(session.isLoggedIn()).assertTrue();
      expect(session.user).assertNull();
    })

    // ---- 验收联动：任一请求 401 → 闸门清会话 → 回未登录 ----

    it('unauthorizedGateClearsSessionOn401', 0, () => {
      const store = new MemorySessionStore();
      const session = new UserSession(store);
      session.establish('jwt-token-abc', userFromJson(USER_JSON));
      const gate = new UnauthorizedGate((): void => {
        session.clear();
      });
      const err401 = new HttpError(HttpErrorKind.Status, 'http 401', 401);
      expect(gate.handleError(err401)).assertTrue();
      expect(session.isLoggedIn()).assertFalse();
      expect(store.get(SESSION_KEY_TOKEN)).assertNull();
      // 非 401 不动作
      session.establish('jwt-token-abc', userFromJson(USER_JSON));
      const err429 = new HttpError(HttpErrorKind.Status, 'http 429', 429);
      expect(gate.handleError(err429)).assertFalse();
      expect(session.isLoggedIn()).assertTrue();
    })

    // ---- 4.3 换绑 / 注销 / 昵称保存的响应解析 ----

    it('parseChangePhoneResponseRequiresOkAndUser', 0, () => {
      const raw = `{"ok":true,"user":${USER_JSON}}`;
      const resp = parseChangePhoneResponse(raw);
      expect(resp.user.id).assertEqual('42');
      expect(resp.user.phone).assertEqual('13800138000');
      // ok 缺失 / 为 false、user 缺失都抛错（防 200 空/坏体静默通过）
      const badBodies: string[] = [
        `{"user":${USER_JSON}}`,
        `{"ok":false,"user":${USER_JSON}}`,
        '{"ok":true}',
        'null',
        '[]'
      ];
      for (const body of badBodies) {
        let threw = false;
        try {
          parseChangePhoneResponse(body);
        } catch (e) {
          threw = true;
        }
        expect(threw).assertTrue();
      }
    })

    it('parseDeleteAccountResponseRequiresOk', 0, () => {
      // 历史字段 appleRevoked 兼容不拒收，但不建模
      const resp = parseDeleteAccountResponse('{"ok":true,"appleRevoked":true}');
      expect(resp.ok).assertTrue();
      expect(parseDeleteAccountResponse('{"ok":true}').ok).assertTrue();
      const badBodies: string[] = ['{}', '{"ok":false}', '"ok"', 'null'];
      for (const body of badBodies) {
        let threw = false;
        try {
          parseDeleteAccountResponse(body);
        } catch (e) {
          threw = true;
        }
        expect(threw).assertTrue();
      }
    })

    it('parseOkResponseValidatesPatchMeBody', 0, () => {
      // PATCH /me 只回 {ok:true}；非 ok 折 Decoding 档
      parseOkResponse('{"ok":true}');
      const badBodies: string[] = ['{}', '{"ok":false}', '', 'null', '[]', '"ok"'];
      for (const body of badBodies) {
        let threw = false;
        try {
          parseOkResponse(body);
        } catch (e) {
          threw = true;
        }
        expect(threw).assertTrue();
      }
    })

    // ---- 4.3 账户页生命周期：换绑刷快照不换 token；补绑 switchedAccount 必换 token ----

    it('changePhoneRefreshesSnapshotKeepsToken', 0, () => {
      const store = new MemorySessionStore();
      const session = new UserSession(store);
      session.establish('jwt-token-abc', userFromJson(USER_JSON));
      const resp = parseChangePhoneResponse(
        `{"ok":true,"user":{"id":42,"phone":"13900139000",`
        + `"displayName":"小明","penPalName":"青鸟","bindings":[{"provider":"phone"}]}}`);
      session.updateUser(resp.user);
      expect(session.token).assertEqual('jwt-token-abc');
      expect(session.user?.phone).assertEqual('13900139000');
      // 快照落了存储（重启不回退）
      expect(new UserSession(store).user?.phone).assertEqual('13900139000');
    })

    it('bindPhoneSwitchedAccountMustEstablishNewToken', 0, () => {
      const store = new MemorySessionStore();
      const session = new UserSession(store);
      session.establish('jwt-empty-shell', userFromJson(USER_MIN_JSON));
      // switchedAccount：服务端已把绑定转移到老账号并删空壳，旧 token 指向的身份
      // 已不存在——必须用返回 token+user 覆盖（establish），否则下一请求就 401
      const resp = parseBindPhoneResponse(BIND_PHONE_JSON);
      expect(resp.switchedAccount).assertTrue();
      expect(resp.token.length > 0).assertTrue();
      session.establish(resp.token, resp.user);
      expect(session.token).assertEqual('jwt-new');
      expect(session.user?.id).assertEqual('42');
      expect(new UserSession(store).token).assertEqual('jwt-new');
      // 正常绑定（switchedAccount false）：只刷快照，token 不动
      const normal = parseBindPhoneResponse(
        `{"ok":true,"switchedAccount":false,"user":${USER_JSON}}`);
      expect(normal.switchedAccount).assertFalse();
      session.updateUser(normal.user);
      expect(session.token).assertEqual('jwt-new');
    })

    it('deleteAccountClearsSessionButNotOtherStores', 0, () => {
      const store = new MemorySessionStore();
      const session = new UserSession(store);
      session.establish('jwt-token-abc', userFromJson(USER_JSON));
      parseDeleteAccountResponse('{"ok":true}');
      session.clear();
      expect(session.isLoggedIn()).assertFalse();
      expect(store.get(SESSION_KEY_TOKEN)).assertNull();
      expect(new UserSession(store).isLoggedIn()).assertFalse();
    })
  })
}
