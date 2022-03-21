%%--------------------------------------------------------------------
%% Copyright (c) 2020-2022 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------
-module(emqx_connector).

-export([config_key_path/0]).

-export([ parse_connector_id/1
        , connector_id/2
        ]).

-export([ list_raw/0
        , lookup_raw/1
        , lookup_raw/2
        , create_dry_run/2
        , update/2
        , update/3
        , delete/1
        , delete/2
        ]).

-export([ post_config_update/5
        ]).

config_key_path() ->
    [connectors].

-dialyzer([{nowarn_function, [post_config_update/5]}, error_handling]).
post_config_update([connectors, Type, Name], '$remove', _, _OldConf, _AppEnvs) ->
    ConnId = connector_id(Type, Name),
    try foreach_linked_bridges(ConnId, fun(#{type := BType, name := BName}) ->
            throw({dependency_bridges_exist, emqx_bridge:bridge_id(BType, BName)})
        end)
    catch throw:Error -> {error, Error}
    end;
post_config_update([connectors, Type, Name], _Req, NewConf, OldConf, _AppEnvs) ->
    ConnId = connector_id(Type, Name),
    foreach_linked_bridges(ConnId,
        fun(#{type := BType, name := BName}) ->
            BridgeConf = emqx:get_config([bridges, BType, BName]),
            case emqx_bridge:update(BType, BName, {BridgeConf#{connector => OldConf},
                    BridgeConf#{connector => NewConf}}) of
                ok -> ok;
                {error, Reason} -> error({update_bridge_error, Reason})
            end
        end).

connector_id(Type0, Name0) ->
    Type = bin(Type0),
    Name = bin(Name0),
    <<Type/binary, ":", Name/binary>>.

parse_connector_id(ConnectorId) ->
    case string:split(bin(ConnectorId), ":", all) of
        [Type, Name] -> {binary_to_atom(Type, utf8), binary_to_atom(Name, utf8)};
        _ -> error({invalid_connector_id, ConnectorId})
    end.

list_raw() ->
    lists:foldl(fun({Type, NameAndConf}, Connectors) ->
            lists:foldl(fun({Name, RawConf}, Acc) ->
                   [RawConf#{<<"type">> => Type, <<"name">> => Name} | Acc]
                end, Connectors, maps:to_list(NameAndConf))
        end, [], maps:to_list(emqx:get_raw_config(config_key_path(), #{}))).

lookup_raw(Id) when is_binary(Id) ->
    {Type, Name} = parse_connector_id(Id),
    lookup_raw(Type, Name).

lookup_raw(Type, Name) ->
    case emqx:get_raw_config(config_key_path() ++ [Type, Name], not_found) of
        not_found -> {error, not_found};
        Conf -> {ok, Conf#{<<"type">> => Type, <<"name">> => Name}}
    end.

create_dry_run(Type, Conf) ->
    emqx_bridge:create_dry_run(Type, Conf).

update(Id, Conf) when is_binary(Id) ->
    {Type, Name} = parse_connector_id(Id),
    update(Type, Name, Conf).

update(Type, Name, Conf) ->
    emqx_conf:update(config_key_path() ++ [Type, Name], Conf, #{override_to => cluster}).

delete(Id) when is_binary(Id) ->
    {Type, Name} = parse_connector_id(Id),
    delete(Type, Name).

delete(Type, Name) ->
    emqx_conf:remove(config_key_path() ++ [Type, Name], #{override_to => cluster}).

bin(Bin) when is_binary(Bin) -> Bin;
bin(Str) when is_list(Str) -> list_to_binary(Str);
bin(Atom) when is_atom(Atom) -> atom_to_binary(Atom, utf8).

foreach_linked_bridges(ConnId, Do) ->
    lists:foreach(fun
        (#{raw_config := #{<<"connector">> := ConnId0}} = Bridge) when ConnId0 == ConnId ->
            Do(Bridge);
        (_) -> ok
    end, emqx_bridge:list()).