# Changelog

## [1.5.0](https://github.com/wsdjeg/job.nvim/compare/v1.4.1...v1.5.0) (2026-02-24)


### Features

* add `job.is_running(id)` function ([b04bf21](https://github.com/wsdjeg/job.nvim/commit/b04bf21e8f8a001d9555d3894e4aa50cc8e17a04))
* add job.wait(id, timeout) function ([f15e41a](https://github.com/wsdjeg/job.nvim/commit/f15e41a40302c483decedffc3b3111b92a5f254a))


### Bug Fixes

* add function annotations ([6c2d365](https://github.com/wsdjeg/job.nvim/commit/6c2d365356af6ab75c332f5b640f85d2c3665c2f))

## [1.4.1](https://github.com/wsdjeg/job.nvim/compare/v1.4.0...v1.4.1) (2026-02-12)


### Bug Fixes

* annotations improved and code format ([9cc4553](https://github.com/wsdjeg/job.nvim/commit/9cc4553b4426aae328c1c9135a9dd7f464678f49))
* buffering was not correctly processed ([#8](https://github.com/wsdjeg/job.nvim/issues/8)) ([980fdb2](https://github.com/wsdjeg/job.nvim/commit/980fdb2db08726ae1fa4dcb99f43d90c96fdb372))
* fix buffered_data function ([e8aa319](https://github.com/wsdjeg/job.nvim/commit/e8aa31928a0389b2024dd9ad655122bbc85acae2))

## [1.4.0](https://github.com/wsdjeg/job.nvim/compare/v1.3.0...v1.4.0) (2025-12-07)


### Features

* add `opt.text` option ([377b891](https://github.com/wsdjeg/job.nvim/commit/377b8910a457dc0728d947e71b06323eac84310d))


### Bug Fixes

* remove text opt ([afe1c14](https://github.com/wsdjeg/job.nvim/commit/afe1c14407cf2355b8f5937dbd6f81eb4dcf4d12))

## [1.3.0](https://github.com/wsdjeg/job.nvim/compare/v1.2.0...v1.3.0) (2025-12-07)


### Features

* support encoding option ([5654b20](https://github.com/wsdjeg/job.nvim/commit/5654b202dc915bcfd3f4988888225f277dfd800f))

## [1.2.0](https://github.com/wsdjeg/job.nvim/compare/v1.1.0...v1.2.0) (2025-11-22)


### Features

* add luarocks support ([c638f11](https://github.com/wsdjeg/job.nvim/commit/c638f11a9e376d72168b1b2f0c9dce65b992f7de))

## [1.1.0](https://github.com/wsdjeg/job.nvim/compare/v1.0.0...v1.1.0) (2025-11-02)


### Features

* **start:** add JobOpts class ([af6acb4](https://github.com/wsdjeg/job.nvim/commit/af6acb431f9a2cecee4cd05e0594cefdced44dbd))
* **start:** check opts.cwd ([9929d8b](https://github.com/wsdjeg/job.nvim/commit/9929d8b91e9302bf21aae0252a6c8d67f477f01d))


### Bug Fixes

* fix job std_data_eof ([141c371](https://github.com/wsdjeg/job.nvim/commit/141c3717332591bb07188e5603a413216367cc0a))
* fix JobOpts fields ([1d7a6e2](https://github.com/wsdjeg/job.nvim/commit/1d7a6e21aae3040707e1c28ca2149b6a8b51e05f))
* **handle:** handle spawn error ([dbea759](https://github.com/wsdjeg/job.nvim/commit/dbea75994c13fd30761de9b4e951d5e3d6dd488c))

## 1.0.0 (2025-09-06)


### Features

* make job.stop support specific single ([29ad3c5](https://github.com/wsdjeg/job.nvim/commit/29ad3c5a8cf9a75a54ab4f9910f8979f6eefe589))


### Bug Fixes

* **cmd:** use exepath for windows ([04203b7](https://github.com/wsdjeg/job.nvim/commit/04203b732ebc8ac1a3a9c1b6b345a025f1eeb083))
* make sure opts is not nil ([81c1d8f](https://github.com/wsdjeg/job.nvim/commit/81c1d8fa31f3a4eb560ef9c75d92db3642f93409))
* skip jobid = nil ([10f7759](https://github.com/wsdjeg/job.nvim/commit/10f775971be42952453429805ac54c7f794aabe1))
