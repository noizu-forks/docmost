import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { createMockAbilityFactory } from '../test-helpers/casl.mock';
import { SpacesController } from './spaces.controller';

describe('SpacesController (v1)', () => {
  const user = { id: 'user_1', role: 'admin' } as any;
  const workspace = { id: 'ws_1' } as any;

  function createController(overrides: { spaces?: any; abilities?: any } = {}) {
    const spaceService = {
      getSpaceInfo: jest
        .fn()
        .mockResolvedValue({ id: 'space_1', name: 'Space' }),
      createSpace: jest
        .fn()
        .mockResolvedValue({ id: 'space_1', name: 'Space' }),
      updateSpace: jest
        .fn()
        .mockResolvedValue({ id: 'space_1', name: 'Renamed' }),
    } as any;
    const spaceMemberService = {
      getUserSpaces: jest.fn().mockResolvedValue({
        items: [{ id: 'space_1' }],
        meta: { hasNextPage: false },
      }),
    } as any;
    const spaceMemberRepo = {
      getUserRolesForSpaces: jest.fn().mockResolvedValue([]),
      getUserSpaceRoles: jest.fn().mockResolvedValue([{ userId: 'user_1', role: 'writer' }]),
    } as any;

    const abilities = overrides.abilities ?? {
      spaceAbility: createMockAbilityFactory([
        { action: 'read', subject: 'settings' },
        { action: 'manage', subject: 'settings' },
        { action: 'create', subject: 'Page' },
      ]),
      workspaceAbility: createMockAbilityFactory([
        { action: 'manage', subject: 'space' },
      ]),
    };

    const controller = new SpacesController(
      overrides.spaces?.spaceService ?? spaceService,
      overrides.spaces?.spaceMemberService ?? spaceMemberService,
      overrides.spaces?.spaceMemberRepo ?? spaceMemberRepo,
      abilities.spaceAbility,
      abilities.workspaceAbility,
    );

    return { controller, spaceService, spaceMemberService, spaceMemberRepo };
  }

  it('lists spaces in the {data, meta} envelope with membership', async () => {
    const { controller } = createController();

    const result = await controller.getSpaces({ limit: 10 }, user);

    expect(result.data[0]).toMatchObject({
      id: 'space_1',
      membership: { userId: 'user_1' },
    });
    expect(result.meta.nextCursor).toBeNull();
  });

  it('returns a single space with membership', async () => {
    const { controller } = createController();

    const result = await controller.getSpace('space_1', user, workspace);

    expect(result.id).toBe('space_1');
    expect(result.membership.role).toBe('writer');
  });

  it('creates a space with workspace manage ability', async () => {
    const { controller, spaceService } = createController();

    await controller.createSpace(
      { name: 'Space', slug: 'space' },
      user,
      workspace,
    );

    expect(spaceService.createSpace).toHaveBeenCalledWith(
      user,
      'ws_1',
      { name: 'Space', slug: 'space' },
    );
  });

  it('patches a space via space settings ability', async () => {
    const { controller, spaceService } = createController();

    const result = await controller.updateSpace(
      'space_1',
      { name: 'Renamed' },
      user,
      workspace,
    );

    expect(result.name).toBe('Renamed');
    expect(spaceService.updateSpace).toHaveBeenCalledWith(
      { spaceId: 'space_1', name: 'Renamed', description: undefined },
      'ws_1',
    );
  });

  it('forbids when the read ability is missing', async () => {
    const { controller } = createController({
      abilities: {
        spaceAbility: createMockAbilityFactory([]),
        workspaceAbility: createMockAbilityFactory([]),
      },
    });

    await expect(
      controller.getSpace('space_1', user, workspace),
    ).rejects.toThrow(ForbiddenException);
  });

  it('404s on an unknown space', async () => {
    const { controller } = createController({
      spaces: {
        spaceService: {
          getSpaceInfo: jest.fn().mockResolvedValue(null),
          createSpace: jest.fn(),
          updateSpace: jest.fn(),
        },
      },
    });

    await expect(
      controller.getSpace('space_x', user, workspace),
    ).rejects.toThrow('Space not found');
  });

  it('skips role lookup for an empty space list', async () => {
    const { controller, spaceMemberRepo } = createController({
      spaces: {
        spaceMemberService: {
          getUserSpaces: jest
            .fn()
            .mockResolvedValue({ items: [], meta: { hasNextPage: false } }),
        },
      },
    });

    const result = await controller.getSpaces({ limit: 10 }, user);

    expect(result.data).toEqual([]);
    expect(spaceMemberRepo.getUserRolesForSpaces).not.toHaveBeenCalled();
  });

  it('tolerates spaces without membership role rows', async () => {
    const { controller } = createController({
      spaces: {
        spaceMemberService: {
          getUserSpaces: jest.fn().mockResolvedValue({
            items: [{ id: 'space_1' }, { id: 'space_2' }],
            meta: { hasNextPage: false },
          }),
        },
        spaceMemberRepo: {
          getUserRolesForSpaces: jest
            .fn()
            .mockResolvedValue([{ spaceId: 'space_2', role: 'writer' }]),
          getUserSpaceRoles: jest.fn().mockResolvedValue([]),
        },
      },
    });

    const result = await controller.getSpaces({ limit: 10 }, user);

    expect((result.data[0] as any).membership.role).toBeUndefined();
    expect((result.data[1] as any).membership.role).toBe('writer');
  });
});
