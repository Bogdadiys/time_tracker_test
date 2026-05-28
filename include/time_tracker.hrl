%% logger macroses
-include_lib("kernel/include/logger.hrl").
-define(DEBUG(Format, Args), ?LOG_DEBUG(Format, Args)).
-define(INFO(Format, Args), ?LOG_INFO(Format, Args)).
-define(NOTICE(Format, Args), ?LOG_NOTICE(Format, Args)).
-define(NOTICE(Format), ?LOG_NOTICE(Format)).
-define(WARNING(Format, Args), ?LOG_WARNING(Format, Args)).
-define(ERROR(Format), ?LOG_ERROR(Format)).
-define(ERROR(Format, Args), ?LOG_ERROR(Format, Args)).