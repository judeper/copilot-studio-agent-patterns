import type { Config } from 'jest';

const config: Config = {
    rootDir: '..',
    testEnvironment: 'jest-environment-jsdom',
    preset: 'ts-jest',

    // TypeScript transform — use test-specific tsconfig with CommonJS output
    transform: {
        '^.+\\.tsx?$': ['ts-jest', {
            tsconfig: '<rootDir>/tsconfig.test.json',
        }],
    },

    // Match test files in __tests__ directories under AssistantDashboard
    testMatch: ['<rootDir>/AssistantDashboard/**/__tests__/**/*.test.ts?(x)'],

    // Setup files — jest-dom matchers and matchMedia mock
    setupFilesAfterEnv: ['<rootDir>/test/jest.setup.ts'],

    // Module resolution — CSS imports resolve to identity proxy
    moduleNameMapper: {
        '\\.(css|less|scss)$': 'identity-obj-proxy',
    },

    // Coverage collection — enable via --coverage flag or test:coverage script.
    // Kept false by default so that `jest --passWithNoTests` succeeds before
    // tests exist (coverage threshold check fails on missing data).
    collectCoverage: false,
    collectCoverageFrom: [
        'AssistantDashboard/**/*.{ts,tsx}',
        '!AssistantDashboard/generated/**',
        '!AssistantDashboard/index.ts',
    ],

    // Per-file 80% coverage threshold via glob pattern.
    // The `global` key is required by Jest types; per-file enforcement uses the
    // glob key which checks each matched file individually.
    coverageThreshold: {
        global: {},
        './AssistantDashboard/**/*.{ts,tsx}': {
            branches: 80,
            functions: 80,
            lines: 80,
            statements: 80,
        },
    },
};

export default config;
