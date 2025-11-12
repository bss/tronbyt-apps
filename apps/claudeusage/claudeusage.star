"""
Applet: Claude Usage
Summary: Display Claude API usage data
Description: Shows token and dollar usage from Claude API for account, workspace, or user.
Author: bss
"""

load("cache.star", "cache")
load("encoding/json.star", "json")
load("http.star", "http")
load("humanize.star", "humanize")
load("render.star", "render")
load("schema.star", "schema")
load("time.star", "time")

CACHE_KEY_PREFIX = "claude_usage_cache"
CACHE_TTL_SECONDS = 3600  # 1 hour

ANTHROPIC_API_BASE = "https://api.anthropic.com"

TIMESPAN_TO_LOOKBACK_DAYS = {
    "1d": 1,
    "7d": 7,
    "14d": 14,
    "30d": 30,
}

def parse_claude_response(response):
    """Parse Claude API response and return data or error."""
    if response.status_code == 401:
        return (None, "Invalid API key")
    elif response.status_code == 403:
        return (None, "Access forbidden - Admin API key required")
    elif response.status_code == 404:
        # Try to get more details from the error response
        json_data = response.json()
        if json_data != None:
            error_obj = json_data.get("error") or {}
            error_msg = error_obj.get("message") or "Resource not found"
            return (None, error_msg)
        return (None, "Resource not found - check endpoint/ID")
    elif response.status_code != 200:
        # Try to get error message from response
        json_data = response.json()
        if json_data != None:
            error_obj = json_data.get("error") or {}
            error_msg = error_obj.get("message") or "API error"
            return (None, "{}: {}".format(error_msg, response.status_code))
        return (None, "API error: {}".format(response.status_code))

    json_data = response.json()
    # The claude_code API returns data directly in the "data" array
    data = json_data.get("data", [])
    has_more = json_data.get("has_more", False)
    next_page = json_data.get("next_page", None)
    
    return (data, None, has_more, next_page)

def format_date_string(unix_timestamp):
    """Format Unix timestamp as YYYY-MM-DD string."""
    dt = time.from_timestamp(unix_timestamp)
    # Format as YYYY-MM-DD (Go reference time format)
    return dt.format("2006-01-02")

def fetch_claude_code_usage_for_day(admin_api_key, date_str, page_token=None):
    """Fetch Claude Code usage data for a single day."""
    headers = {
        "x-api-key": admin_api_key,
        "anthropic-version": "2023-06-01",
        "Content-Type": "application/json",
    }

    # Build params - API requires starting_at in YYYY-MM-DD format
    params = {
        "starting_at": date_str,
        "limit": "1000",  # Max limit to get all records
    }
    
    if page_token != None:
        params["page"] = page_token

    url = "{}/v1/organizations/usage_report/claude_code".format(ANTHROPIC_API_BASE)
    response = http.get(url, headers=headers, params=params, ttl_seconds=CACHE_TTL_SECONDS)
    data, error, has_more, next_page = parse_claude_response(response)

    if error != None:
        return (None, error, False, None)

    return (data, None, has_more, next_page)

def fetch_all_pages_for_day(admin_api_key, date_str, page_token, all_data):
    """Recursively fetch all pages for a single day."""
    day_data, error, has_more, next_page = fetch_claude_code_usage_for_day(
        admin_api_key, date_str, page_token
    )
    
    if error != None:
        return (None, error)
    
    if day_data != None:
        all_data.extend(day_data)
    
    if has_more and next_page != None:
        return fetch_all_pages_for_day(admin_api_key, date_str, next_page, all_data)
    
    return (all_data, None)

def fetch_claude_usage(admin_api_key, timespan):
    """Fetch usage data from Claude Code API for all days in timespan."""
    # Calculate date range
    now = time.now()
    num_days = TIMESPAN_TO_LOOKBACK_DAYS[timespan]
    
    all_data = []
    
    # Fetch data for each day in the range
    for day_offset in range(num_days):
        # Calculate date for this day (going backwards from today)
        day_timestamp = now.unix - (day_offset * 24 * 60 * 60)
        date_str = format_date_string(day_timestamp)
        
        # Fetch all pages for this day
        result_data, error = fetch_all_pages_for_day(admin_api_key, date_str, None, all_data)
        
        if error != None:
            return (None, error)
        
        all_data = result_data

    return (all_data, None)

def fetch_usage_with_cache(admin_api_key, timespan):
    """Fetch usage data with caching."""
    cache_key = "{}-{}-{}".format(
        CACHE_KEY_PREFIX, 
        admin_api_key[:32] if len(admin_api_key) > 32 else admin_api_key, 
        timespan,
    )

    data_cached = cache.get(cache_key)
    if data_cached != None and data_cached != "null":
        data = json.decode(data_cached)
        return (data, None)

    data, error = fetch_claude_usage(admin_api_key, timespan)
    if error == None and data != None:
        cache.set(cache_key, json.encode(data), ttl_seconds=CACHE_TTL_SECONDS)
    return (data, error)

def filter_data(data, filter_actor_type, filter_actor_id, filter_model):
    """Filter data by actor_type, actor_id, and model."""
    if data == None:
        return None
    
    if type(data) != "list":
        return None
    
    filtered = []
    
    for entry in data:
        # Filter by actor type
        if filter_actor_type != "" and filter_actor_type != "all":
            actor = entry.get("actor") or {}
            actor_type = actor.get("type", "")
            if actor_type != filter_actor_type:
                continue
        
        # Filter by actor ID (email_address for user_actor, api_key_name for api_actor)
        if filter_actor_id != "":
            actor = entry.get("actor") or {}
            actor_type = actor.get("type", "")
            if actor_type == "user_actor":
                email = actor.get("email_address", "")
                if email != filter_actor_id:
                    continue
            elif actor_type == "api_actor":
                api_key_name = actor.get("api_key_name", "")
                if api_key_name != filter_actor_id:
                    continue
            else:
                # Unknown actor type, skip if filter is set
                continue
        
        # Filter by model - check all models in model_breakdown
        if filter_model != "":
            model_breakdown = entry.get("model_breakdown", [])
            if type(model_breakdown) == "list":
                # Check if any model matches
                found = False
                for model_entry in model_breakdown:
                    model_name = model_entry.get("model", "")
                    if model_name == filter_model:
                        found = True
                        break
                if not found:
                    continue
        
        filtered.append(entry)
    
    return filtered

def aggregate_data(data):
    """Aggregate tokens and costs from Claude Code usage data."""
    if data == None:
        return None

    if type(data) != "list":
        return None

    total_tokens = 0
    total_cost_cents = 0

    for entry in data:
        # Aggregate tokens and costs from model_breakdown
        model_breakdown = entry.get("model_breakdown", [])
        if type(model_breakdown) == "list":
            for model_entry in model_breakdown:
                # Sum up all token types: input, output, cache_read, cache_creation
                tokens_obj = model_entry.get("tokens", {})
                input_tokens = tokens_obj.get("input", 0) or 0
                output_tokens = tokens_obj.get("output", 0) or 0
                cache_read = tokens_obj.get("cache_read", 0) or 0
                cache_creation = tokens_obj.get("cache_creation", 0) or 0
                total_tokens = total_tokens + int(input_tokens) + int(output_tokens) + int(cache_read) + int(cache_creation)
                
                # Sum up costs (already in USD cents)
                cost_obj = model_entry.get("estimated_cost", {})
                cost_amount = cost_obj.get("amount", 0) or 0
                total_cost_cents = total_cost_cents + int(cost_amount)

    # Convert cents to dollars
    total_cost = float(total_cost_cents) / 100.0
    result = {
        "tokens": total_tokens,
        "cost": total_cost,
    }
    return result

def humanize_tokens(tokens):
    """Format token count with K/M/B postfixes."""
    tokens_int = int(tokens)
    
    if tokens_int >= 1000000000:
        # Billions
        billions = float(tokens_int) / 1000000000.0
        return humanize.float("#.#", billions) + "B"
    elif tokens_int >= 1000000:
        # Millions
        millions = float(tokens_int) / 1000000.0
        return humanize.float("#.#", millions) + "M"
    elif tokens_int >= 1000:
        # Thousands
        thousands = float(tokens_int) / 1000.0
        return humanize.float("#.#", thousands) + "K"
    else:
        # Less than 1000, no postfix
        return str(tokens_int)

def render_error(error_text):
    """Render error message."""
    print("Error")
    print(error_text)
    return [
        render.Row(
            cross_align="center",
            main_align="center",
            children=[
                render.WrappedText(align="center", content=error_text),
            ],
        ),
    ]

def render_usage(header, usage_data):
    """Render usage data in two columns."""
    tokens = usage_data.get("tokens", 0)
    cost = usage_data.get("cost", 0.0)

    tokens_str = humanize_tokens(tokens)
    # Format cost as currency
    cost_str = "$" + humanize.float("#,##0.00", cost)

    children = []

    # Header row
    if header:
        children.append(
            render.Row(
                expanded=True,
                main_align="center",
                cross_align="center",
                children=[
                    render.Marquee(
                        width=64,
                        align="center",
                        child=render.Text(content=header),
                    ),
                ],
            ),
        )

    # Data rows - two rows with one centered column each
    # Tokens row
    children.append(
        render.Row(
            expanded=True,
            main_align="center",
            cross_align="center",
            children=[
                render.Marquee(
                    width=64,
                    align="center",
                    child=render.Text(content=tokens_str, font="6x13"),
                ),
            ],
        ),
    )
    # Cost row
    children.append(
        render.Row(
            expanded=True,
            main_align="center",
            cross_align="center",
            children=[
                render.Marquee(
                    width=64,
                    align="center",
                    child=render.Text(content=cost_str, font="6x13"),
                ),
            ],
        ),
    )

    return children

def fetch_render_children(config):
    """Fetch usage data and render children."""
    admin_api_key = config.get("admin_api_key") or ""
    timespan = config.get("timespan") or "7d"
    filter_actor_type = config.get("filter_actor_type") or "all"
    filter_actor_id = config.get("filter_actor_id") or ""
    filter_model = config.get("filter_model") or ""
    header = config.get("header") or "Claude Usage"

    if not admin_api_key:
        return render_error("Admin API key required")

    data, error = fetch_usage_with_cache(admin_api_key, timespan)
    if error != None:
        return render_error(error)

    filtered_data = filter_data(data, filter_actor_type, filter_actor_id, filter_model)

    if filtered_data == None or len(filtered_data) == 0:
        return render_error("No data available")
    
    agg_data = aggregate_data(filtered_data)

    return render_usage(header, agg_data)

def main(config):
    """Main entry point."""
    children = fetch_render_children(config)

    return render.Root(
        child=render.Column(
            main_align="space_evenly",
            cross_align="center",
            expanded=True,
            children=children,
        ),
    )

def get_schema():
    """Get configuration schema."""
    timespan_options = [
        schema.Option(display="1 day", value="1d"),
        schema.Option(display="7 days", value="7d"),
        schema.Option(display="14 days", value="14d"),
        schema.Option(display="30 days", value="30d"),
    ]
    
    actor_type_options = [
        schema.Option(display="All", value="all"),
        schema.Option(display="User Actor", value="user_actor"),
        schema.Option(display="API Actor", value="api_actor"),
    ]
    
    return schema.Schema(
        version="1",
        fields=[
            schema.Text(
                id="admin_api_key",
                name="Anthropic Admin API Key",
                desc="Your Anthropic Admin API key (starts with sk-ant-admin) from https://console.anthropic.com/. Required for usage data.",
                icon="lock",
                default="",
            ),
            schema.Dropdown(
                id="timespan",
                name="Time Span",
                desc="How far back to fetch usage data",
                icon="clock",
                default=timespan_options[1].value,
                options=timespan_options,
            ),
            schema.Dropdown(
                id="filter_actor_type",
                name="Actor Type Filter",
                desc="Filter by actor type: user_actor (email) or api_actor (API key name)",
                icon="user",
                default=actor_type_options[0].value,
                options=actor_type_options,
            ),
            schema.Text(
                id="filter_actor_id",
                name="Actor ID",
                desc="Optional: Filter by email address (for user_actor) or API key name (for api_actor)",
                icon="magnifyingGlass",
                default="",
            ),
            schema.Text(
                id="filter_model",
                name="Model Filter",
                desc="Optional: Filter by model (e.g., claude-sonnet-4-5-20250929). Leave empty for all models.",
                icon="magnifyingGlass",
                default="",
            ),
            schema.Text(
                id="header",
                name="Header Text",
                desc="Custom header text to display above usage data",
                icon="font",
                default="Claude Usage",
            ),
        ],
    )

