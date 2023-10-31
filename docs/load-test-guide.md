# Process of adding a load test to a standard library repository

_Authors_: @dilanSachi  
_Reviewers_: @shafreenAnfar @daneshk  
_Created_: 2022/08/15  
_Updated_: 2021/08/15

This section describes the steps to add a load test to a standard library repository. The tests are running in an AKS cluster.

<img src="_resources/load-test-setup.png" alt="drawing"/>

Most of the following steps are adapted from [here](https://github.com/ballerina-platform/ballerina-performance-cloud/blob/main/README.md).

1. All the tests in the standard library should reside inside `load-tests` directory in the repository root.

2. Create a directory inside `load-tests` for the test. We will call it `test_sample` here.

3. The test should have four directories inside.
    1. deployment
    2. results
    3. scripts
    4. src

4. The `src` directory should contain the ballerina package that has to be load tested.
   This project should have `cloud = "k8s"` entry inside Ballerina.toml, and it should have Cloud.toml file to
   configure the docker and  Kubernetes artifacts.

```toml
[container.image]
repository= "ballerina" # Do not change this entry.
name="test_sample" # Docker image name should be same as package name

[cloud.deployment] 
# Resource Allocations Change these according to your scenario needs
# min_memory="256Mi" 
# max_memory="512Mi"
# min_cpu="200m"
# max_cpu="500m"
[cloud.deployment.autoscaling]
# min_replicas=1
# max_replicas=1
```
3. The `deployment` directory should contain the additional kubernetes artifacts that should be applied on top of
   c2c generated yaml. This will be done using Kustomize. `ingress.yaml` and `kustomization.yaml` is mandatory here.
   You can add any additional yamls you require for the deployment in this directory (helper pods, mysql etc).

kustomization.yaml
```yaml
resources:
  - test_sample.yaml # this is the name of generated yaml from c2c. you can execute bal build on the src dir to find the exact name
  - ingress.yaml
```
ingress.yaml
```yaml
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test_sample
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  rules:
  - host: bal.perf.test
    http:
      paths:
      - path: "/"
        pathType: Prefix
        backend:
          service:
            name: sample-svc # generated service name from c2c. you might need to verify this by manually reading the generated yaml.
            port:
              number: 9090
  tls:
  - hosts:
    - "bal.perf.test"

```
4. The `scripts` directory is used to hold the scripts required for load test execution. It must contain run.sh file
   which will be responsible for running the load test. You can include the .jmx file and access it via the
   directory via $scriptsDir variable in the run.sh file.

   You can additionally have `pre_run.sh` (ex - to install dependencies for required test) and `post_run.sh` (ex -
   to modify results csv) in the same directory.

Sample run.sh file
```bash
set -e
source base-scenario.sh

jmeter -n -t "$scriptsDir/"http-post-request.jmx -l "$resultsDir/"original.jtl -Jusers=50 -Jduration=1200 -Jhost=bal.perf.test -Jport=443 -Jprotocol=https -Jpath=passthrough $payload_flags
```

* For the load tests that cannot use `jmeter` as a load testing tool, you can use any required tool and can set up the tool in the `pre_run.sh` and 
format the results according to the required format in the `post_run.sh`. A sample usage can be found in [gRPC load tests](https://github.com/ballerina-platform/module-ballerina-grpc/tree/master/load-tests/route_guide_bidirectional_streaming/scripts) which has used the tool `ghz` instead of `jmeter`.

5. The `results` directory should contain summary.csv file with the following header. Results of the tests will be
   appended to this file.
```csv
Label,# Samples,Average,Median,90% Line,95% Line,99% Line,Min,Max,Error %,Throughput,Received KB/sec,Std. Dev.,Date,Payload,Users
```

6. When your test is ready, you can commit your test suite to the stdlib repository under `ballerina-platform` and execute
   https://github.com/ballerina-platform/ballerina-performance-cloud/actions/workflows/stdlib_workflow.yml by giving
   the repository name as an input.

* Instead of manually invoking the above workflow, we have added a [`trigger-load-tests`](https://github.com/ballerina-platform/module-ballerina-grpc/blob/master/.github/workflows/trigger-load-tests.yml) workflow 
to each stdlib repo to trigger the load test from the stdlib repo, and it is configured to automatically run the load test daily.

* Once the load test is run, the results from the load test will be sent to the relevant stdlib via `repository_dispatch` in GitHub workflows.
This triggers the workflow [`process-load-test-result`](https://github.com/ballerina-platform/module-ballerina-grpc/blob/master/.github/workflows/process-load-test-result.yml) and this workflow will create a PR to automatically merge the load test results to the `results.csv` in the relevant load test.
If the load test failed for some reason, above workflow will fail, and it will be displayed in the [stdlib dashboard](https://github.com/ballerina-platform/ballerina-standard-library).

* If you are adding a load test for the first time to a stdlib repo, you will have to add both `trigger-load-tests` and `process-load-test-result` workflows to the repo.
