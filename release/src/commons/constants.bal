const CONFIG_FILE_PATH = "./resources/stdlib_modules.json";

public const API_PATH = "https://api.github.com/repos/ballerina-platform";
public const WORKFLOW_STATUS_PATH = "/actions/workflows/build-master.yml/runs?per_page=1";
public const DISPATCHES = "/dispatches";

public const ACCESS_TOKEN_ENV = "GITHUB_TOKEN";

const ACCEPT_HEADER_KEY = "Accept";
const ACCEPT_HEADER_VALUE = "application/vnd.github.v3+json";
const AUTH_HEADER_KEY = "Authorization";

public const RETRY_COUNT = 3;
public const RETRY_INTERVAL = 10000;
public const RETRY_BACKOFF_FACTOR = 2.0;
public const RETRY_MAX_WAIT_TIME = 2;

public const SLEEP_INTERVAL = 30000; // Sleep for 30 seconds between checks
public const MAX_WAIT_CYCLES = 80; // Max wait time is 40 minutes
