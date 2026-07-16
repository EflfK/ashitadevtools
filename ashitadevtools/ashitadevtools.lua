addon.name      = 'ashitadevtools';
addon.author    = 'EflfK';
addon.version   = '0.1.0';
addon.desc      = 'Local-only Ashita addon development MCP bridge.';
addon.link      = 'https://github.com/EflfK/ashitadevtools';

require('common');

local chat = require('chat');
local socket = nil;

local bridge = T{
    host = '127.0.0.1',
    port = 19772,
    server = nil,
    clients = T{ },
    enabled = true,
    lifecycle_requests = 0,
    log_requests = 0,
    last_lifecycle_request = nil,
    last_log_request = nil,
    command_log = T{ },
    max_command_log_entries = 25,
};

-- Empty means any strictly validated addon name is allowed.
-- Add names here to restrict lifecycle commands to known local dev addons.
local allowed_addons = T{ };

local function log_info(message)
    print(chat.header(addon.name):append(chat.message(message)));
end

local function log_error(message)
    print(chat.header(addon.name):append(chat.error(message)));
end

local function safe_read(reader, default)
    local ok, value = pcall(reader);
    if (ok and value ~= nil) then
        return value;
    end

    return default;
end

local function clean_string(value)
    if (value == nil) then
        return '';
    end

    return tostring(value):gsub('%z', ''):trim();
end

local function json_escape(value)
    value = tostring(value);
    value = value:gsub('\\', '\\\\');
    value = value:gsub('"', '\\"');
    value = value:gsub('\b', '\\b');
    value = value:gsub('\f', '\\f');
    value = value:gsub('\n', '\\n');
    value = value:gsub('\r', '\\r');
    value = value:gsub('\t', '\\t');
    return value;
end

local function json_value(value)
    if (value == nil) then
        return 'null';
    end

    local value_type = type(value);
    if (value_type == 'number') then
        return tostring(value);
    end

    if (value_type == 'boolean') then
        return value and 'true' or 'false';
    end

    return ('"%s"'):fmt(json_escape(value));
end

local function append_json_field(fields, name, value)
    table.insert(fields, ('"%s":%s'):fmt(name, json_value(value)));
end

local function append_json_raw_field(fields, name, value)
    table.insert(fields, ('"%s":%s'):fmt(name, value));
end

local function json_array(values)
    return ('[%s]'):fmt(table.concat(values, ','));
end

local function json_string_array(values)
    local escaped = { };
    for _, value in ipairs(values) do
        table.insert(escaped, json_value(value));
    end

    return json_array(escaped);
end

local function url_decode(value)
    if (value == nil) then
        return '';
    end

    value = tostring(value):gsub('+', ' ');
    value = value:gsub('%%(%x%x)', function (hex)
        return string.char(tonumber(hex, 16));
    end);
    return value;
end

local function parse_query(query)
    local params = { };
    if (query == nil or #query == 0) then
        return params;
    end

    for part in query:gmatch('[^&]+') do
        local key, value = part:match('^([^=]*)=?(.*)$');
        key = url_decode(key):lower();
        value = url_decode(value);
        if (#key > 0) then
            params[key] = value;
        end
    end

    return params;
end

local function bounded_number(value, default, min, max)
    local numeric = tonumber(value);
    if (numeric == nil) then
        numeric = default;
    end

    numeric = math.floor(numeric);
    if (numeric < min) then
        return min;
    end

    if (numeric > max) then
        return max;
    end

    return numeric;
end

local function close_client(index)
    local client = bridge.clients[index];
    if (client ~= nil and client.sock ~= nil) then
        pcall(function () client.sock:close(); end);
    end

    bridge.clients:remove(index);
end

local function close_server()
    for i = #bridge.clients, 1, -1 do
        close_client(i);
    end

    if (bridge.server ~= nil) then
        pcall(function () bridge.server:close(); end);
        bridge.server = nil;
    end
end

local function ensure_socket()
    if (socket ~= nil) then
        return true;
    end

    local ok, mod = pcall(require, 'socket');
    if (not ok or mod == nil) then
        log_error('LuaSocket is not available; bridge cannot listen.');
        return false;
    end

    socket = mod;
    return true;
end

local function start_server()
    if (bridge.server ~= nil) then
        return true;
    end

    if (not ensure_socket()) then
        return false;
    end

    local server, err = socket.bind(bridge.host, bridge.port);
    if (server == nil) then
        log_error(('Failed to bind %s:%d: %s'):fmt(bridge.host, bridge.port, tostring(err)));
        return false;
    end

    server:settimeout(0);
    bridge.server = server;
    log_info(('Listening on http://%s:%d.'):fmt(bridge.host, bridge.port));
    return true;
end

local function get_character_name()
    local party = AshitaCore:GetMemoryManager():GetParty();
    return clean_string(safe_read(function () return party:GetMemberName(0); end, ''));
end

local function allowlist_enabled()
    for _, _ in pairs(allowed_addons) do
        return true;
    end

    return false;
end

local function addon_is_allowlisted(name)
    if (not allowlist_enabled()) then
        return true;
    end

    local wanted = name:lower();
    for _, configured in pairs(allowed_addons) do
        if (clean_string(configured):lower() == wanted) then
            return true;
        end
    end

    return false;
end

local function allowed_addons_json()
    local names = { };
    for _, configured in pairs(allowed_addons) do
        local name = clean_string(configured);
        if (#name > 0) then
            table.insert(names, name);
        end
    end

    table.sort(names);
    return json_string_array(names);
end

local function validate_addon_name(name)
    name = clean_string(name);

    if (#name == 0) then
        return false, 'addon name is required';
    end

    if (#name > 64) then
        return false, 'addon name is too long';
    end

    if (name:match('^[A-Za-z0-9_%-]+$') == nil) then
        return false, 'addon name must match ^[A-Za-z0-9_-]+$';
    end

    if (not addon_is_allowlisted(name)) then
        return false, 'addon name is not in the local allowlist';
    end

    return true, nil, name;
end

local function command_log_entry_json(entry)
    local fields = { };
    append_json_field(fields, 'capturedAt', entry.captured_at);
    append_json_field(fields, 'operation', entry.operation);
    append_json_field(fields, 'addon', entry.addon);
    append_json_field(fields, 'command', entry.command);
    return ('{%s}'):fmt(table.concat(fields, ','));
end

local function command_log_json()
    local entries = { };
    for _, entry in ipairs(bridge.command_log) do
        table.insert(entries, command_log_entry_json(entry));
    end

    return json_array(entries);
end

local function record_lifecycle_command(operation, name, command)
    local timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ');

    bridge.lifecycle_requests = bridge.lifecycle_requests + 1;
    bridge.last_lifecycle_request = timestamp;
    bridge.command_log:append(T{
        captured_at = timestamp,
        operation = operation,
        addon = name,
        command = command,
    });

    while (#bridge.command_log > bridge.max_command_log_entries) do
        bridge.command_log:remove(1);
    end

    log_info(('Queued lifecycle command: %s'):fmt(command));
end

local function status_json()
    local status = bridge.server ~= nil and 'listening' or 'stopped';
    local fields = { };

    append_json_field(fields, 'ok', true);
    append_json_field(fields, 'status', status);
    append_json_field(fields, 'host', bridge.host);
    append_json_field(fields, 'port', bridge.port);
    append_json_field(fields, 'baseUrl', ('http://%s:%d'):fmt(bridge.host, bridge.port));
    append_json_field(fields, 'clients', #bridge.clients);
    append_json_field(fields, 'lifecycleRequests', bridge.lifecycle_requests);
    append_json_field(fields, 'logRequests', bridge.log_requests);
    append_json_field(fields, 'lastLifecycleRequest', bridge.last_lifecycle_request);
    append_json_field(fields, 'lastLogRequest', bridge.last_log_request);
    append_json_raw_field(fields, 'allowedOperations', json_string_array({ 'load', 'unload', 'reload', 'status', 'ashita-log-tail' }));
    append_json_field(fields, 'addonNamePattern', '^[A-Za-z0-9_-]+$');
    append_json_field(fields, 'allowlistMode', allowlist_enabled() and 'explicit-allowlist' or 'strict-name-validation');
    append_json_raw_field(fields, 'allowedAddons', allowed_addons_json());
    append_json_raw_field(fields, 'recentLifecycleCommands', command_log_json());

    return ('{%s}'):fmt(table.concat(fields, ','));
end

local function read_tail_lines(path, limit)
    local file = io.open(path, 'r');
    if (file == nil) then
        return nil;
    end

    local lines = { };
    for line in file:lines() do
        table.insert(lines, clean_string(line));
        if (#lines > limit) then
            table.remove(lines, 1);
        end
    end

    file:close();
    return lines;
end

local function ashita_log_tail_json(params)
    local line_count = bounded_number(params.lines, 100, 1, 500);
    local character = get_character_name();
    local log_date = os.date('%Y.%m.%d');
    local path = ('%schatlogs\\%s_%s.log'):fmt(AshitaCore:GetInstallPath(), character, log_date);
    local lines = read_tail_lines(path, line_count);
    local line_json = { };

    bridge.log_requests = bridge.log_requests + 1;
    bridge.last_log_request = os.date('!%Y-%m-%dT%H:%M:%SZ');

    if (lines ~= nil) then
        for _, line in ipairs(lines) do
            table.insert(line_json, json_value(line));
        end
    end

    local fields = { };
    append_json_field(fields, 'ok', true);
    append_json_field(fields, 'schema', 1);
    append_json_field(fields, 'capturedAt', bridge.last_log_request);
    append_json_field(fields, 'character', character);
    append_json_field(fields, 'logDate', log_date);
    append_json_field(fields, 'source', 'current-character local Ashita chat log');
    append_json_field(fields, 'requestedLines', line_count);
    append_json_field(fields, 'available', lines ~= nil);
    append_json_field(fields, 'lineCount', lines ~= nil and #lines or 0);
    append_json_raw_field(fields, 'lines', json_array(line_json));

    if (lines == nil) then
        append_json_field(fields, 'warning', 'Current character chat log file was not found.');
    end

    return ('{%s}'):fmt(table.concat(fields, ','));
end

local function lifecycle_result_json(operation, name, command)
    local fields = { };
    append_json_field(fields, 'ok', true);
    append_json_field(fields, 'queued', true);
    append_json_field(fields, 'operation', operation);
    append_json_field(fields, 'addon', name);
    append_json_field(fields, 'command', command);
    append_json_field(fields, 'capturedAt', bridge.last_lifecycle_request);
    return ('{%s}'):fmt(table.concat(fields, ','));
end

local function error_json(message)
    local fields = { };
    append_json_field(fields, 'ok', false);
    append_json_field(fields, 'error', message);
    return ('{%s}'):fmt(table.concat(fields, ','));
end

local function lifecycle_operation(operation, params)
    local ok, err, name = validate_addon_name(params.name);
    if (not ok) then
        return 400, error_json(err);
    end

    local command = nil;
    if (operation == 'load') then
        command = ('/addon load %s'):fmt(name);
    elseif (operation == 'unload') then
        command = ('/addon unload %s'):fmt(name);
    elseif (operation == 'reload') then
        command = ('/addon reload %s'):fmt(name);
    else
        return 404, error_json('unknown lifecycle operation');
    end

    AshitaCore:GetChatManager():QueueCommand(1, command);
    record_lifecycle_command(operation, name, command);
    return 200, lifecycle_result_json(operation, name, command);
end

local function send_http_response(client, status, content_type, body)
    local reason = status == 200 and 'OK'
        or status == 400 and 'Bad Request'
        or status == 404 and 'Not Found'
        or status == 405 and 'Method Not Allowed'
        or 'Error';
    body = body or '';

    local response = table.concat({
        ('HTTP/1.1 %d %s'):fmt(status, reason),
        ('Content-Type: %s'):fmt(content_type or 'text/plain; charset=utf-8'),
        ('Content-Length: %d'):fmt(#body),
        'Connection: close',
        '',
        body,
    }, '\r\n');

    pcall(function () client.sock:send(response); end);
    client.closed = true;
end

local function handle_http_request(client, line)
    local method, path = line:match('^(%u+)%s+([^%s]+)%s+HTTP/%d%.%d');
    if (method == nil) then
        return false;
    end

    local raw_path = path;
    local query = '';
    path, query = raw_path:match('^([^?]*)%??(.*)$');
    local params = parse_query(query);

    if (method == 'GET' and (path == '/' or path == '/status')) then
        send_http_response(client, 200, 'application/json; charset=utf-8', status_json());
        return true;
    end

    if (method == 'GET' and path == '/ashita-log-tail') then
        send_http_response(client, 200, 'application/json; charset=utf-8', ashita_log_tail_json(params));
        return true;
    end

    if (path == '/addon/load' or path == '/addon/unload' or path == '/addon/reload') then
        if (method ~= 'POST') then
            send_http_response(client, 405, 'application/json; charset=utf-8', error_json('lifecycle operations require POST'));
            return true;
        end

        local operation = path:match('^/addon/([A-Za-z]+)$');
        local status, body = lifecycle_operation(operation, params);
        send_http_response(client, status, 'application/json; charset=utf-8', body);
        return true;
    end

    if (method ~= 'GET' and method ~= 'POST') then
        send_http_response(client, 405, 'application/json; charset=utf-8', error_json('method not allowed'));
        return true;
    end

    send_http_response(client, 404, 'application/json; charset=utf-8', error_json('not found'));
    return true;
end

local function process_line(client, line)
    local request = line:gsub('\r', ''):trim();
    if (#request == 0) then
        return;
    end

    if (handle_http_request(client, request)) then
        return;
    end

    send_http_response(client, 400, 'application/json; charset=utf-8', error_json('bad request'));
end

local function accept_clients()
    if (bridge.server == nil) then
        return;
    end

    while true do
        local client = bridge.server:accept();
        if (client == nil) then
            return;
        end

        client:settimeout(0);
        bridge.clients:append(T{ sock = client, buffer = '' });
    end
end

local function poll_clients()
    for i = #bridge.clients, 1, -1 do
        local client = bridge.clients[i];
        local chunk, err, partial = client.sock:receive(4096);
        local data = chunk or partial;

        if (data ~= nil and #data > 0) then
            client.buffer = client.buffer .. data;

            while true do
                local newline = client.buffer:find('\n', 1, true);
                if (newline == nil) then
                    break;
                end

                local line = client.buffer:sub(1, newline - 1);
                client.buffer = client.buffer:sub(newline + 1);
                process_line(client, line);

                if (client.closed) then
                    break;
                end
            end
        end

        if (client.closed or err == 'closed') then
            close_client(i);
        end
    end
end

local function print_help()
    log_info('Available commands:');
    print(chat.header(addon.name):append(chat.message('/adt status - Show endpoint status.')));
    print(chat.header(addon.name):append(chat.message('/adt restart - Restart the local listener.')));
end

ashita.events.register('load', 'load_cb', function ()
    start_server();
end);

ashita.events.register('unload', 'unload_cb', function ()
    close_server();
end);

ashita.events.register('command', 'command_cb', function (e)
    local args = e.command:args();
    if (#args == 0 or not args[1]:any('/adt', '/ashitadevtools')) then
        return;
    end

    e.blocked = true;

    if (#args == 1 or args[2]:any('help')) then
        print_help();
        return;
    end

    if (args[2]:any('status')) then
        local status = bridge.server ~= nil and 'listening' or 'stopped';
        log_info(('Status: %s on http://%s:%d, clients=%d, lifecycleRequests=%d, logRequests=%d, lastLifecycleRequest=%s, lastLogRequest=%s.'):fmt(
            status,
            bridge.host,
            bridge.port,
            #bridge.clients,
            bridge.lifecycle_requests,
            bridge.log_requests,
            bridge.last_lifecycle_request or '-',
            bridge.last_log_request or '-'));
        return;
    end

    if (args[2]:any('restart')) then
        close_server();
        start_server();
        return;
    end

    print_help();
end);

ashita.events.register('d3d_present', 'present_cb', function ()
    if (not bridge.enabled) then
        return;
    end

    if (bridge.server == nil and not start_server()) then
        return;
    end

    accept_clients();
    poll_clients();
end);
