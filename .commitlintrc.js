module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'type-enum': [
      2,
      'always',
      [
        'feat',
        'fix',
        'perf',
        'docs',
        'build',
        'ci',
        'test',
        'chore',
        'style',
        'refactor'
      ]
    ],
    'subject-case': [0]
  }
};
