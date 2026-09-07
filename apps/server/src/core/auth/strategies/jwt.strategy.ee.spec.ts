import { JwtType } from '../dto/jwt-payload';
import { JwtStrategy } from './jwt.strategy';

jest.mock('@nestjs/passport', () => ({
  // mirror the real mixin: forwards config args and appends a verify callback
  PassportStrategy: (Base: any) =>
    class extends Base {
      constructor(...args: any[]) {
        super(...args, () => {});
      }
    },
}));

// Virtual ee modules: an enterprise build resolves these requires, so the
// strategy must prefer them over the community API-key service.
class EeApiKeyService {}
class EeOAuthStrategyService {}

jest.mock('../../../ee/api-key/api-key.service', () => ({
  ApiKeyService: EeApiKeyService,
}), { virtual: true });

jest.mock('../../../ee/oauth/services/oauth-strategy.service', () => ({
  OAuthStrategyService: EeOAuthStrategyService,
}), { virtual: true });

describe('JwtStrategy (enterprise build, ee modules present)', () => {
  const user = { id: 'user_1', name: 'User' };
  const workspace = { id: 'ws_1' };

  let registry: Map<unknown, unknown>;

  function createStrategy() {
    const moduleRef = {
      get: jest.fn((token: unknown) => {
        if (!registry.has(token)) {
          throw new Error(`unknown provider: ${String(token)}`);
        }
        return registry.get(token);
      }),
    };
    const strategy = new JwtStrategy(
      { findById: jest.fn() } as any,
      { findById: jest.fn() } as any,
      { findActiveById: jest.fn() } as any,
      { trackActivity: jest.fn() } as any,
      { getAppSecret: () => 'test-secret' } as any,
      moduleRef as any,
    );
    return { strategy, moduleRef };
  }

  function req(): any {
    return { raw: { headers: { host: 'docmost.test' }, workspaceId: 'ws_1' } };
  }

  beforeEach(() => {
    registry = new Map();
  });

  it('prefers the ee api-key service over the community fallback', async () => {
    const eeService = {
      validateApiKey: jest.fn().mockResolvedValue({ user, workspace }),
    };
    registry.set(EeApiKeyService, eeService);
    const { strategy } = createStrategy();

    const result = await strategy.validate(req(), {
      sub: 'user_1',
      workspaceId: 'ws_1',
      apiKeyId: 'key_1',
      type: JwtType.API_KEY,
    } as any);

    expect(eeService.validateApiKey).toHaveBeenCalledWith(
      expect.objectContaining({ apiKeyId: 'key_1' }),
    );
    expect(result).toEqual({ user, workspace, authType: JwtType.API_KEY });
  });

  it('delegates OAUTH_ACCESS tokens to the ee oauth service', async () => {
    const oauthService = {
      validateOAuthToken: jest.fn().mockResolvedValue({ user, workspace }),
    };
    registry.set(EeOAuthStrategyService, oauthService);
    const { strategy } = createStrategy();

    const result = await strategy.validate(req(), {
      sub: 'user_1',
      workspaceId: 'ws_1',
      type: JwtType.OAUTH_ACCESS,
    } as any);

    expect(oauthService.validateOAuthToken).toHaveBeenCalledWith(
      expect.objectContaining({ type: JwtType.OAUTH_ACCESS }),
      { workspaceId: 'ws_1', host: 'docmost.test' },
    );
    expect(result).toEqual({ user, workspace, authType: JwtType.OAUTH_ACCESS });
  });
});
