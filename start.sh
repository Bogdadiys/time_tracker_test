#! /bin/bash
erl -pa deps/*/ebin ebin -config env/dev.config -s time_tracker_test_app -sname time_tracker_test
