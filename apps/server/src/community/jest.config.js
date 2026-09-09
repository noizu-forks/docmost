/**
 * Scoped test/coverage config for the community API module (AGPL fork).
 *
 * Runs only the community suites plus the JWT-strategy spec that covers the
 * community API-key fallback, and enforces the fork's coverage gate without
 * touching upstream root config (run from apps/server):
 *
 *   npx jest -c src/community/jest.config.js
 *   npx jest -c src/community/jest.config.js --coverage
 */
const pkg = require('../../package.json');

module.exports = {
  ...pkg.jest,
  // keep the package.json rootDir (src) so the inherited moduleNameMapper
  // entries (<rootDir>/database, <rootDir>/../../../packages/...) still resolve
  rootDir: '..',
  // inherited testRegex conflicts with our scoped testMatch
  testRegex: null,
  testMatch: [
    '<rootDir>/community/**/*.spec.ts',
    '<rootDir>/core/auth/strategies/jwt.strategy*.spec.ts',
  ],
  collectCoverageFrom: [
    'community/**/*.(t|j)s',
    '!community/**/*.spec.ts',
    '!community/jest.config.js',
    '!community/test-helpers/**',
    'core/auth/strategies/jwt.strategy.ts',
    '!core/auth/strategies/jwt.strategy*.spec.ts',
  ],
  // under the repo-root /coverage dir that .gitignore already excludes
  coverageDirectory: '../../coverage/community',
  // babel-plugin-istanbul's test-exclude@6.0.0 crashes against the installed
  // glob major; V8 coverage needs no extra transform pass.
  coverageProvider: 'v8',
  coverageThreshold: {
    global: {
      lines: 85,
      branches: 85,
    },
  },
};
