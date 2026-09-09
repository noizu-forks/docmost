import { UnauthorizedException } from '@nestjs/common';
import { JwtType } from '../dto/jwt-payload';
import { JwtStrategy } from './jwt.strategy';
import { ApiKeyService as CommunityApiKeyService } from '../../../community/api-key/api-key.service';

jest.mock('@nestjs/passport', () => ({
  // mirror the real mixin: forwards config args and appends a verify callback
  PassportStrategy: (Base: any) =>
    class extends Base {
      constructor(...args: any[]) {
        super(...args, () => {});
      }
    },
}));

// No ee/ mocks are registered in this file: the strategy's require() of the
// enterprise modules fails, exactly as in an AGPL (community) build.
describe('JwtStrategy (community build, no ee modules)', () => {
  const user = { id: 'user_1', name: 'User' };
  const workspace = { id: 'ws_1' };

  let userRepo: any;
  let workspaceRepo: any;
  let userSessionRepo: any;
  let sessionActivityService: any;
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
      userRepo,
      workspaceRepo,
      userSessionRepo,
      sessionActivityService,
      { getAppSecret: () => 'test-secret' } as any,
      moduleRef as any,
    );
    return { strategy, moduleRef };
  }

  function req(overrides: Record<string, any> = {}): any {
    return { raw: { headers: { host: 'docmost.test' }, ...overrides } };
  }

  beforeEach(() => {
    registry = new Map();
    userRepo = { findById: jest.fn().mockResolvedValue(user) };
    workspaceRepo = { findById: jest.fn().mockResolvedValue(workspace) };
    userSessionRepo = {
      findActiveById: jest.fn().mockResolvedValue({
        userId: 'user_1',
        workspaceId: 'ws_1',
      }),
    };
    sessionActivityService = { trackActivity: jest.fn() };
  });

  describe('payload triage', () => {
    it('rejects a payload without a workspace', async () => {
      const { strategy } = createStrategy();

      await expect(
        strategy.validate(req(), { sub: 'user_1' } as any),
      ).rejects.toThrow(UnauthorizedException);
    });

    it('rejects a payload whose workspace mismatches the request', async () => {
      const { strategy } = createStrategy();

      await expect(
        strategy.validate(req({ workspaceId: 'ws_other' }), {
          sub: 'user_1',
          workspaceId: 'ws_1',
          type: JwtType.ACCESS,
        } as any),
      ).rejects.toThrow('Workspace does not match');
    });

    it('rejects an unknown payload type', async () => {
      const { strategy } = createStrategy();

      await expect(
        strategy.validate(req(), {
          sub: 'user_1',
          workspaceId: 'ws_1',
          type: 'exchange',
        } as any),
      ).rejects.toThrow(UnauthorizedException);
    });
  });

  describe('ACCESS tokens', () => {
    const payload = { sub: 'user_1', workspaceId: 'ws_1', type: JwtType.ACCESS };

    it('returns the user, workspace and authType', async () => {
      const { strategy } = createStrategy();

      const result = await strategy.validate(req(), payload as any);

      expect(result).toEqual({ user, workspace, authType: JwtType.ACCESS });
    });

    it('rejects when the workspace is gone', async () => {
      workspaceRepo.findById.mockResolvedValue(null);
      const { strategy } = createStrategy();

      await expect(strategy.validate(req(), payload as any)).rejects.toThrow(
        UnauthorizedException,
      );
    });

    it('rejects a missing user', async () => {
      userRepo.findById.mockResolvedValue(null);
      const { strategy } = createStrategy();

      await expect(strategy.validate(req(), payload as any)).rejects.toThrow(
        UnauthorizedException,
      );
    });

    it('rejects a disabled user', async () => {
      userRepo.findById.mockResolvedValue({ ...user, deactivatedAt: new Date() });
      const { strategy } = createStrategy();

      await expect(strategy.validate(req(), payload as any)).rejects.toThrow(
        UnauthorizedException,
      );
    });

    it('rejects a session that no longer resolves', async () => {
      userSessionRepo.findActiveById.mockResolvedValue(null);
      const { strategy } = createStrategy();

      await expect(
        strategy.validate(req(), { ...payload, sessionId: 'sess_1' } as any),
      ).rejects.toThrow(UnauthorizedException);
    });

    it('rejects a session belonging to another user or workspace', async () => {
      userSessionRepo.findActiveById.mockResolvedValue({
        userId: 'someone_else',
        workspaceId: 'ws_1',
      });
      const { strategy } = createStrategy();

      await expect(
        strategy.validate(req(), { ...payload, sessionId: 'sess_1' } as any),
      ).rejects.toThrow(UnauthorizedException);
    });

    it('tracks activity and tags the request for a live session', async () => {
      const request = req();
      const { strategy } = createStrategy();

      const result = await strategy.validate(request, {
        ...payload,
        sessionId: 'sess_1',
      } as any);

      expect(result.authType).toBe(JwtType.ACCESS);
      expect(request.raw.sessionId).toBe('sess_1');
      expect(sessionActivityService.trackActivity).toHaveBeenCalledWith(
        'sess_1',
        'user_1',
        'ws_1',
      );
    });
  });

  describe('API_KEY tokens (community fallback)', () => {
    const payload = {
      sub: 'user_1',
      workspaceId: 'ws_1',
      apiKeyId: 'key_1',
      type: JwtType.API_KEY,
    };

    it('delegates to the community service when no ee module is bundled', async () => {
      const communityService = {
        validateApiKey: jest.fn().mockResolvedValue({ user, workspace }),
      };
      registry.set(CommunityApiKeyService, communityService);
      const { strategy } = createStrategy();

      const result = await strategy.validate(req(), payload as any);

      expect(communityService.validateApiKey).toHaveBeenCalledWith(payload);
      expect(result).toEqual({ user, workspace, authType: JwtType.API_KEY });
    });

    it('401s when neither the ee nor the community module is available', async () => {
      const { strategy } = createStrategy();

      await expect(strategy.validate(req(), payload as any)).rejects.toThrow(
        'API Key module missing',
      );
    });
  });

  describe('OAUTH_ACCESS tokens (community build)', () => {
    const payload = {
      sub: 'user_1',
      workspaceId: 'ws_1',
      type: JwtType.OAUTH_ACCESS,
    };

    it('401s when the enterprise oauth module is missing', async () => {
      const { strategy } = createStrategy();

      await expect(strategy.validate(req(), payload as any)).rejects.toThrow(
        'Enterprise OAuth module missing',
      );
    });
  });
});
