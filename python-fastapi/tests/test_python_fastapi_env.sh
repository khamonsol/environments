#!/bin/bash

set -euo pipefail
ROOT=$(dirname $0)/../..
source $ROOT/test_utils/utils.sh

TEST_ID=$(generate_test_id)
echo "TEST_ID = $TEST_ID"

tmp_dir="/tmp/test-$TEST_ID"
mkdir -p $tmp_dir

cleanup() {
    log "Cleaning up..."
    clean_resource_by_id $TEST_ID
    rm -rf $tmp_dir
}

if [ -z "${TEST_NOCLEANUP:-}" ]; then
    trap cleanup EXIT
else
    log "TEST_NOCLEANUP is set; not cleaning up test artifacts afterwards."
fi

env_v1api=python-fastapi-v1-$TEST_ID
env_v2api=python-fastapi-v2-$TEST_ID
fn1=test-python-fastapi-env-1-$TEST_ID
fn2=test-python-fastapi-env-2-$TEST_ID
fn3=test-python-fastapi-env-3-$TEST_ID
fn4=test-python-fastapi-env-4-$TEST_ID
fn5=test-python-fastapi-env-5-$TEST_ID

PYTHON_FASTAPI_RUNTIME_IMAGE=python-fastapi-env
PYTHON_FASTAPI_BUILDER_IMAGE=python-fastapi-builder

log "Creating v1api environment ..."
log "PYTHON_FASTAPI_RUNTIME_IMAGE = $PYTHON_FASTAPI_RUNTIME_IMAGE"
fission env create \
    --name $env_v1api \
    --image $PYTHON_FASTAPI_RUNTIME_IMAGE \

log "Creating v2api environment ..."
log "PYTHON_FASTAPI_RUNTIME_IMAGE = $PYTHON_FASTAPI_RUNTIME_IMAGE     PYTHON_FASTAPI_BUILDER_IMAGE = $PYTHON_FASTAPI_BUILDER_IMAGE"
fission env create \
    --name $env_v2api \
    --image $PYTHON_FASTAPI_RUNTIME_IMAGE \
    --builder $PYTHON_FASTAPI_BUILDER_IMAGE
timeout 180s bash -c "wait_for_builder $env_v2api"

log "Creating package ..."
pushd $ROOT/python-fastapi/tests/src
zip -r $tmp_dir/src-pkg.zip *
popd
pkg=$(generate_test_id)
fission package create --name $pkg --src $tmp_dir/src-pkg.zip --env $env_v2api
timeout 60s bash -c "waitBuild $pkg"


log "===== 1. test env with v1 api ====="
fission fn create --name $fn1 --env $env_v1api --code $ROOT/python-fastapi/examples/hello.py
fission route create --name $fn1 --function $fn1 --url /$fn1 --method GET
sleep 3     # Waiting for router to catch up
timeout 60 bash -c "test_fn $fn1 'Hello, world!'"


log "===== 2. test entrypoint = '' ====="
fission fn create --name $fn2 --env $env_v2api --pkg $pkg
fission route create --name $fn2 --function $fn2 --url /$fn2 --method GET
sleep 3     # Waiting for router to catch up
timeout 60 bash -c "test_fn $fn2 'THIS_IS_MAIN_MAIN'"


log "===== 3. test entrypoint = func ====="
fission fn create --name $fn3 --env $env_v2api --pkg $pkg --entrypoint func
fission route create --name $fn3 --function $fn3 --url /$fn3 --method GET
sleep 3     # Waiting for router to catch up
timeout 60 bash -c "test_fn $fn3 'THIS_IS_MAIN_FUNC'"


log "===== 4. test entrypoint = foo.bar ====="
fission fn create --name $fn4 --env $env_v2api --pkg $pkg --entrypoint foo.bar
fission route create --name $fn4 --function $fn4 --url /$fn4 --method GET
sleep 3     # Waiting for router to catch up
timeout 60 bash -c "test_fn $fn4 'THIS_IS_FOO_BAR'"


log "===== 5. test entrypoint = sub_mod.altmain.entrypoint ====="
fission fn create --name $fn5 --env $env_v2api --pkg $pkg --entrypoint sub_mod.altmain.entrypoint
fission route create --name $fn5 --function $fn5 --url /$fn5 --method GET
sleep 3     # Waiting for router to catch up
timeout 60 bash -c "test_fn $fn5 'THIS_IS_ALTMAIN_ENTRYPOINT'"


log "Test PASSED"
