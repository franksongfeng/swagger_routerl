%%% @author Leonardo Rossi <leonardo.rossi@studenti.unipr.it>
%%% @copyright (C) 2016 Leonardo Rossi
%%%
%%% This software is free software; you can redistribute it and/or
%%% modify it under the terms of the GNU General Public License as
%%% published by the Free Software Foundation; either version 2 of the
%%% License, or (at your option) any later version.
%%%
%%% This software is distributed in the hope that it will be useful, but
%%% WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%%% General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License
%%% along with this software; if not, write to the Free Software Foundation,
%%% Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307, USA.
%%%
%%% @doc Transform the swagger file into a Cowboy WebSocket routing table.
%%% @end
-module(swagger_routerl_cowboy_ws).

-author('Leonardo Rossi <leonardo.rossi@studenti.unipr.it').

-export([compile/1, execute/3]).

-export_type([routectx/0]).

-type yaml()     :: swagger_routerl:yaml().
-type routes()   :: list({re:mp(), handler()}).
-type handler()  :: atom().
-type routectx() :: term().
-type appctx()   :: #{routectx => routectx(), routes => routes()}.
-type req()      :: cowboy_req:req().
-type event()    :: map().
-type url()      :: list().

-ifdef(TEST).
-compile(export_all).
-endif.

%%% API functions

-spec compile(yaml()) -> routes().
compile(Yaml) ->
  Paths = proplists:get_value("paths", Yaml),
  lists:map(
    fun({SwaggerPath, _Config}) ->
        {build_regex(SwaggerPath),
         get_filename(SwaggerPath)}
    end, Paths).

-spec execute(event(), req(), appctx()) ->
    {ok, req(), routectx()}
  | {ok, req(), routectx(), hibernate}
  | {reply, cow_ws:frame() | [cow_ws:frame()], req(), routectx()}
  | {reply, cow_ws:frame() | [cow_ws:frame()], req(), routectx(), hibernate}
  | {stop, req(), routectx()}.
execute(Event, Req, AppContext) ->
  Routes = maps:get(routes, AppContext),
  RouteCtx = maps:get(routectx, AppContext),
  case match(maps:get(<<"url">>, Event), Routes) of
    {error, _}=Error -> Error;
    {ok, Handler} ->
      Method = to_atom(maps:get(<<"method">>, Event)),
      try
        Handler:Method(Event, Req, RouteCtx)
      catch
        error:undef -> {error, notdefined}
      end
  end.

%%% Private functions

-spec to_atom(term()) -> atom().
to_atom(Atom) when is_atom(Atom) -> Atom;
to_atom(Binary) when is_binary(Binary) ->
  list_to_atom(binary_to_list(Binary)).


-spec match(url(), routes()) -> {ok, handler()} | {error, notfound}.
match(_Url, []) ->
  {error, notfound};
match(Url, [{MP, Handler} | Rest]) ->
  case re:run(Url, MP) of
    {match, _} -> {ok, Handler};
    _Rest -> match(Url, Rest)
  end.

-spec build_regex(list()) -> re:mp().
build_regex(SwaggerPath) ->
  List = string:tokens(SwaggerPath, "/"),
  RegexList = lists:map(
    fun(El) ->
      case re:run(El, "^{.+}$") of
        {match, _} -> "[\\w\-]+";
        _Rest -> El
      end
    end, List),
  RegEx = "^/" ++ string:join(RegexList, "/") ++ "$",
  {ok, MP} = re:compile(RegEx),
  MP.

-spec get_filename(list()) -> list().
get_filename(PathConfig) ->
  Tokens = string:tokens(PathConfig, "/{}"),
  list_to_atom("ws_" ++ string:join(Tokens, "_")).


