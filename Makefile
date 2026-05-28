PROJECT = time_tracker_test
PROJECT_DESCRIPTION = test project
PROJECT_VERSION = 0.1.0

DEPS = cowboy jsx epgsql liver amqp_client

dep_cowboy      = git https://github.com/ninenines/cowboy.git       2.10.0
dep_jsx         = git https://github.com/talentdeficit/jsx.git      v3.1.0
dep_epgsql      = git https://github.com/epgsql/epgsql.git          4.8.0
dep_liver       = git https://github.com/erlangbureau/liver.git     master
dep_amqp_client = hex 3.12.13

BUILD_DEPS += relx

TEST_DEPS = meck
dep_meck = hex 0.9.2

CONFIG ?= dev
RELX_OPTS = -o _rel/$(CONFIG) --sys_config $(CURDIR)/env/$(CONFIG).config
VM_ARGS_FILE = $(CURDIR)/_rel/$(CONFIG)/time_tracker_test/releases/$(PROJECT_VERSION)/vm.args

RELX_TAR = false

DIALYZER_DIRS = ebin

include erlang.mk
