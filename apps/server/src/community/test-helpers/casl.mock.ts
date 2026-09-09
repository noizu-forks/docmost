/**
 * Test helper: mock Workspace/SpaceAbilityFactory whose createForUser
 * resolves to an ability granting exactly the listed (action, subject) pairs.
 */
export function createMockAbilityFactory(
  rules: { action: string; subject: string }[],
) {
  const can = (action: string, subject: string) =>
    rules.some((rule) => rule.action === action && rule.subject === subject);

  const ability = {
    can,
    cannot: (action: string, subject: string) => !can(action, subject),
    rules,
  };

  const factory = {
    // Sync return on purpose: WorkspaceAbilityFactory.createForUser is sync;
    // callers that await still receive the plain ability value.
    createForUser: jest.fn().mockReturnValue(ability),
  };

  return factory;
}
