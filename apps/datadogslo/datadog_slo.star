"""
Applet: Datadog SLO
Summary: Show status of Datadog SLO
Description: Shows the status and SLI of a SLO from Datadog.
Author: bss
"""

load("cache.star", "cache")
load("encoding/base64.star", "base64")
load("encoding/json.star", "json")
load("http.star", "http")
load("humanize.star", "humanize")
load("render.star", "render")
load("schema.star", "schema")
load("time.star", "time")

ALERT_ICON = base64.decode("""
iVBORw0KGgoAAAANSUhEUgAAAgAAAAIACAYAAAD0eNT6AAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAOxAAADsQBlSsOGwAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAArESURBVHic7d0xbjLJGkBR/MRGRk5MOoEjMpZA7pAFWPIqLHkBDp2zBDJHBC+F5NdbCrOBF1FoSq17Tl7qD2i6ryqp1QoAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgHs8zR4Ayk6b/W32DDPtLkfPIJjkP7MHAAD+fQIAAIIEAAAECQAACBIAABAkAAAgSAAAQJAAAIAgAQAAQQIAAIIEAAAECQAACBIAABAkAAAgSAAAQJCzuGHAabO/jax/fWn/Bc/Xoa9vtbsc218gDLADAABBAgAAggQAAAQJAAAIEgAAECQAACBIAABAkAAAgCABAABBAgAAggQAAAQJAAAIEgAAECQAACBIAABAkAAAgCABAABBAgAAggQAAAQJAAAIEgAAECQAACBIAABAkAAAgCABAABBAgAAggQAAAQJAAAIEgAAECQAACBIAABA0NPsAWCm02Z/G1n/+uIvNNP5OvTzrXaXox+QLDsAABAkAAAgSAAAQJAAAIAgAQAAQQIAAIIEAAAECQAACBIAABAkAAAgSAAAQJAAAIAgAQAAQQIAAIIEAAAErWcPANzvfL1Nvf7ry9PU6wP3swMAAEECAACCBAAABAkAAAgSAAAQJAAAIEgAAECQAACAIAEAAEECAACCBAAABAkAAAgSAAAQJAAAIEgAAECQw7xZtNNmfxtZP/s8+/N1aPzV8+/3gya5z5/tYWj90r//3eXoGcpi2QEAgCABAABBAgAAggQAAAQJAAAIEgAAECQAACBIAABAkAAAgCABAABBAgAAggQAAAQJAAAIEgAAECQAACBoPXsA2k6b/dCB7LPPk2fZRu+f02rs/t1djm5gprEDAABBAgAAggQAAAQJAAAIEgAAECQAACBIAABAkAAAgCABAABBAgAAggQAAAQJAAAIEgAAECQAACBIAABA0Hr2ALBk5+vQcfCr59/vB00yx+j85+1haP3ry9PQeiizAwAAQQIAAIIEAAAECQAACBIAABAkAAAgSAAAQJAAAIAgAQAAQQIAAIIEAAAECQAACBIAABAkAAAgSAAAQNB69gAs22mzv42sd547SzZ6/55WY/+f3eXoD8Td7AAAQJAAAIAgAQAAQQIAAIIEAAAECQAACBIAABAkAAAgSAAAQJAAAIAgAQAAQQIAAIIEAAAECQAACBIAABC0nj0AzHS+Dh3Hvnr+/X7QJE2j3995exha//ryNLQelswOAAAECQAACBIAABAkAAAgSAAAQJAAAIAgAQAAQQIAAIIEAAAECQAACBIAABAkAAAgSAAAQJAAAIAgAQAAQQ7Djjtt9reR9Us/T/18Hfr4w+fZj3p/+5h6/a+fz6nXH/VnexhaP/v+H71/d5fjsv/ADLEDAABBAgAAggQAAAQJAAAIEgAAECQAACBIAABAkAAAgCABAABBAgAAggQAAAQJAAAIEgAAECQAACBIAABAkLOgF+602Q8dCD77PPNRo+ehP/9+P2iS+7y/fQyt/2v794Mmuc//fv87tP7r5/NBk9znz/YwtL7+/9ldjsv+AuLsAABAkAAAgCABAABBAgAAggQAAAQJAAAIEgAAECQAACBIAABAkAAAgCABAABBAgAAggQAAAQJAAAIEgAAELSePQBto+eRP/9+P2gSikbvn/P2MLT+9eVpaD2MsAMAAEECAACCBAAABAkAAAgSAAAQJAAAIEgAAECQAACAIAEAAEECAACCBAAABAkAAAgSAAAQJAAAIEgAAEDQevYAdafN/jay3nniwL1Gnx+n1djza3c5eoBNZAcAAIIEAAAECQAACBIAABAkAAAgSAAAQJAAAIAgAQAAQQIAAIIEAAAECQAACBIAABAkAAAgSAAAQJAAAICg9ewBWLbzdeg48NXz7/eDJoF/3+j9e94ehta/vjwNrafNDgAABAkAAAgSAAAQJAAAIEgAAECQAACAIAEAAEECAACCBAAABAkAAAgSAAAQJAAAIEgAAECQAACAIAEAAEHr2QMs3Wmzv42sd543sFSjz6/Tauz5ubscPUAH2AEAgCABAABBAgAAggQAAAQJAAAIEgAAECQAACBIAABAkAAAgCABAABBAgAAggQAAAQJAAAIEgAAECQAACAof5byaTN2HvXoedizna9DH3/1/Pv9oEm4x/vbx9Trf/18Tr1+3Z/tYWh9/fm1uxyX/QUMsgMAAEECAACCBAAABAkAAAgSAAAQJAAAIEgAAECQAACAIAEAAEECAACCBAAABAkAAAgSAAAQJAAAIEgAAEDQevYAwP2+fj5nj8BEz7/fQ+vP28PQ+teXp6H1zGUHAACCBAAABAkAAAgSAAAQJAAAIEgAAECQAACAIAEAAEECAACCBAAABAkAAAgSAAAQJAAAIEgAAECQAACAoPXsAUadNvvbyPqln2d9vg59/OHzxJnr/e1j6vW/fj6nXp+20ef3aTX2/thdjot+gdgBAIAgAQAAQQIAAIIEAAAECQAACBIAABAkAAAgSAAAQJAAAIAgAQAAQQIAAIIEAAAECQAACBIAABAkAAAgaD17gLrzdeg46tXz7/eDJmGG97ePofV/bf9+0CT3GZ3/6+fzQZNwj9Hnx3l7GFr/+vI0tJ4xdgAAIEgAAECQAACAIAEAAEECAACCBAAABAkAAAgSAAAQJAAAIEgAAECQAACAIAEAAEECAACCBAAABAkAAAhazx7gtNnfRtY7TxqAe4y+P06rsffX7nKc+gKzAwAAQQIAAIIEAAAECQAACBIAABAkAAAgSAAAQJAAAIAgAQAAQQIAAIIEAAAECQAACBIAABAkAAAgSAAAQNDwWcSnzdh5yKPnMc92vg59/NXz7/eDJqHo/e1j6vW/fj6nXp9l+7M9DK2vvz92l+PQF2AHAACCBAAABAkAAAgSAAAQJAAAIEgAAECQAACAIAEAAEECAACCBAAABAkAAAgSAAAQJAAAIEgAAECQAACAoPXsAYD7ff18zh4BWCg7AAAQJAAAIEgAAECQAACAIAEAAEECAACCBAAABAkAAAgSAAAQJAAAIEgAAECQAACAIAEAAEECAACCBAAABK1nD7B0ry9PQ+vP28ODJgFYltHnJ2PsAABAkAAAgCABAABBAgAAggQAAAQJAAAIEgAAECQAACBIAABAkAAAgCABAABBAgAAggQAAAQJAAAIEgAAELSePUCd87ABmMEOAAAECQAACBIAABAkAAAgSAAAQJAAAIAgAQAAQQIAAIIEAAAECQAACBIAABAkAAAgSAAAQJAAAIAgAQAAQdMPoz9t9reR9a8v0z8CAEHn69Dra7W7HKe+wOwAAECQAACAIAEAAEECAACCBAAABAkAAAgSAAAQJAAAIEgAAECQAACAIAEAAEECAACCBAAABAkAAAgSAAAQNPUs4kc4bfZjBzIDwB12l+Oi36F2AAAgSAAAQJAAAIAgAQAAQQIAAIIEAAAECQAACBIAABAkAAAgSAAAQJAAAIAgAQAAQQIAAIIEAAAECQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP6vfwCvytasA1520wAAAABJRU5ErkJggg==
""")

CACHE_KEY_PREFIX = "data_cache"
TIMEWINDOW_TO_LOOKBACK_SECONDS = {
    "1d": 24 * 60 * 60,
    "7d": 7 * 24 * 60 * 60,
    "30d": 30 * 24 * 60 * 60,
    "90d": 90 * 24 * 60 * 60,
}
COLOR_GREEN = "#6ce674"
COLOR_YELLOW = "#fcea44"
COLOR_RED = "#ff5757"

def parse_datadog_response(response):
    if response.status_code == 403:
        return (None, "Invalid API/APP key")

    json_data = response.json()
    error, data = None, None
    if len(json_data.get("errors", []) or []) > 0:
        error = json_data["errors"][0]
    else:
        data = json_data.get("data")
    return (data, error)

def fetch_slo(dd_api_key, dd_app_key, slo_id, timewindow):
    to_ts = time.now().unix
    from_ts = to_ts - TIMEWINDOW_TO_LOOKBACK_SECONDS[timewindow]
    response = http.get(
        "https://api.datadoghq.com/api/v1/slo/{}/history?from_ts={}&to_ts={}".format(slo_id, from_ts, to_ts),
        headers = {
            "DD-API-KEY": dd_api_key,
            "DD-APPLICATION-KEY": dd_app_key,
            "Accept": "application/json",
        },
    )

    data, error = parse_datadog_response(response)
    if error != None:
        return (None, error)

    name = data.get("slo").get("name")
    sli_value = data.get("overall").get("sli_value")
    sli_precision = data.get("overall").get("span_precision")
    thresholds = data.get("thresholds")
    threshold = thresholds.get(timewindow)
    if threshold == None:
        threshold = thresholds.values()[0]
    result = {
        "name": name,
        "timewindow": timewindow,
        "value": sli_value,
        "precision": sli_precision,
        "threshold": threshold,
    }

    return (result, None)

def fetch_slo_with_cache(dd_api_key, dd_app_key, slo_id, timewindow):
    cache_key = "{}-{}-{}-{}-{}".format(CACHE_KEY_PREFIX, dd_api_key, dd_app_key, slo_id, timewindow)

    data_cached = cache.get(cache_key)
    error = None
    if data_cached != None and data_cached != "null":
        data = json.decode(data_cached)
    else:
        data, error = fetch_slo(dd_api_key, dd_app_key, slo_id, timewindow)
        if error != None:
            cache.set(cache_key, json.encode(data), ttl_seconds = 240)
    return (data, error)

def render_error(error_text):
    return [
        render.Row(
            cross_align = "center",
            main_align = "center",
            children = [
                render.Image(width = 18, height = 18, src = ALERT_ICON),
                render.WrappedText(align = "center", content = error_text),
            ],
        ),
    ]

def render_slo(title, timewindow_data):
    name = title or timewindow_data[0].get("name")

    children = [
        render.Row(
            expanded = True,
            main_align = "space_evenly",
            cross_align = "center",
            children = [
                render.Marquee(
                    width = 64,
                    align = "center",
                    child = render.Text(content = name),
                ),
            ],
        ),
    ]
    if len(timewindow_data) == 1:
        slo_font = "6x13"
    elif len(timewindow_data) == 2:
        slo_font = "6x10"
    else:
        slo_font = "CG-pixel-4x5-mono"
    max_precision = max([d.get("precision") for d in timewindow_data])
    for data in timewindow_data:
        value = data.get("value")

        # precision = data.get("precision")
        timewindow = data.get("timewindow")
        precision_str = "".join(["#" for i in range(int(max_precision))])
        formatted_value = "{}%".format(humanize.float("####.{}".format(precision_str), value))
        threshold = data.get("threshold")

        value_color = COLOR_GREEN
        if value < threshold.get("warning", -1):
            value_color = COLOR_YELLOW

        if value < threshold.get("target"):
            value_color = COLOR_RED

        children.append(
            render.Row(
                expanded = True,
                main_align = "space_between",
                cross_align = "center",
                children = [
                    render.Padding(
                        pad = (2, 0, 0, 0),
                        child = render.Text(content = timewindow, font = slo_font),
                    ),
                    render.Padding(
                        pad = (0, 0, 2, 0),
                        child = render.Text(content = formatted_value, font = slo_font, color = value_color),
                    ),
                ],
            ),
        )
    return children

def fetch_render_children(config):
    dd_api_key = config.get("api_key") or ""
    dd_app_key = config.get("app_key") or ""
    slo_id = config.get("slo_id") or ""
    timewindows_to_display = config.get("timewindows_to_display") or "1"
    timewindows_to_display_number = int(timewindows_to_display)
    title = config.get("title")

    timewindows_data = []
    for i in range(timewindows_to_display_number):
        timewindow = config.get("timewindow_{}".format(i + 1)) or "1d"
        data, error = fetch_slo_with_cache(dd_api_key, dd_app_key, slo_id, timewindow)
        if error != None:
            return render_error(error)
        timewindows_data.append(data)

    return render_slo(title, timewindows_data)

def main(config):
    children = fetch_render_children(config)

    return render.Root(
        child = render.Column(
            main_align = "space_evenly",
            cross_align = "center",
            expanded = True,
            children = children,
        ),
    )

def get_schema():
    timewindow_options = [
        schema.Option(
            display = "1 day",
            value = "1d",
        ),
        schema.Option(
            display = "7 days",
            value = "7d",
        ),
        schema.Option(
            display = "30 days",
            value = "30d",
        ),
        schema.Option(
            display = "90 days",
            value = "90d",
        ),
    ]
    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "api_key",
                name = "DataDog API Key",
                desc = "API Key from your settings",
                icon = "lock",
                default = "",
            ),
            schema.Text(
                id = "app_key",
                name = "DataDog Application Key",
                desc = "A DataDog user account Application Key generated by the user",
                icon = "lock",
                default = "",
            ),
            schema.Text(
                id = "slo_id",
                name = "SLO ID",
                desc = "The ID of the SLO to display. Find it in the URL query params when vieweing an SLO in the browser",
                icon = "magnifyingGlass",
                default = "",
            ),
            schema.Text(
                id = "title",
                name = "Title",
                desc = "The title to display for the SLO. If not provided, the name of the SLO will be used.",
                icon = "font",
                default = "",
            ),
            schema.Dropdown(
                id = "timewindows_to_display",
                name = "Amount of time windows to display",
                desc = "The amount of time windows to display. 1, 2, or 3",
                icon = "clock",
                default = "1",
                options = [
                    schema.Option(
                        display = "1",
                        value = "1",
                    ),
                    schema.Option(
                        display = "2",
                        value = "2",
                    ),
                    schema.Option(
                        display = "3",
                        value = "3",
                    ),
                ],
            ),
            schema.Dropdown(
                id = "timewindow_1",
                name = "Time window 1",
                desc = "The lookback time window to display SLI data for time window 1",
                icon = "clock",
                default = timewindow_options[0].value,
                options = timewindow_options,
            ),
            schema.Dropdown(
                id = "timewindow_2",
                name = "Time window 2",
                desc = "The lookback time window to display SLI data for time window 2",
                icon = "clock",
                default = timewindow_options[1].value,
                options = timewindow_options,
            ),
            schema.Dropdown(
                id = "timewindow_3",
                name = "Time window 3",
                desc = "The lookback time window to display SLI data for time window 3",
                icon = "clock",
                default = timewindow_options[2].value,
                options = timewindow_options,
            ),
        ],
    )
