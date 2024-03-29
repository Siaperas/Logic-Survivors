%%
:- use_module(basics, [length/2, member/2, memberchk/2, append/3, select/3, subseq/3, ith/3, reverse/2]).
:- use_module(standard, [datime/1]).

:- import unifiable/3 from constraintLib.

:- import (in)/2, (#>)/2, (#<)/2, (#>=)/2, (#=<)/2, (#=)/2, labeling/2 from bounds.

:- import datime_setrand/0, random/3 from random.

:- import error/3 from error_handler.

:- import fluent_pred/1, event_pred/1, temp_constraint/1 from preprocessor.
:- import reactive_conjunct/1, l_int_body/1, l_events_body/1 from preprocessor.
:- import d_head/1, d_event/1, d_body/1 from preprocessor.

:- import action/1, cacts/1, current_time/1, d_pre/1, event/1 from usermod.
:- import fluent/1, happens/3, initiated/3, l_events/2, l_int/2 from usermod.
:- import l_timeless/2, observe/2, reactive_rule/2, state/1 from usermod.
:- import steps/1, succ_t/2, susp/1, terminated/3, used/1 from usermod.
:- import current_goal/1, depth/1, tried/3, failed/3, option/1 from usermod.
:- import expanded_consequent/2, this_initiated/1 from usermod.

:- [bounds].
?- load_dyn(db).

% query(+P)
%   True if P holds in the augmented state {S*_i, ev*_i, L_int, L_timeless}.
%
query(holds(not(P), Now)) :-
    current_time(Now),
    \+ l_int(holds(P, Now), _),
    \+ state(P).
query(holds(P, Now)) :-
    current_time(Now),
    \+ l_int(holds(P, Now), _),
    state(P).
query(happens(P, Prev, Now)) :-
    current_time(Now),
    succ_t(Prev, Now),
    happens(P, Prev, Now).
query(holds(not(P), Now)) :-
    current_time(Now),
    l_int(holds(P, Now), B),
    \+ holds_all(B).
query(holds(P, Now)) :-
    current_time(Now),
    l_int(holds(P, Now), B),
    holds_all(B).
query(P) :-
    l_timeless(P, B),
    evaluate(B).

% evaluate(+Body)
%
evaluate([]).
evaluate([P|Rest]) :-
    l_timeless(P, _),
    query(P),
    evaluate(Rest).
evaluate([P|Rest]) :-
    call(P),
    evaluate(Rest).

% holds_all(+PL)
%   True if all predicates in PL hold in the augmented state {S*_i, ev*_i,
%   L_int, L_timeless}.
%
holds_all([]).
holds_all([P|Rest]) :-
    query(P),
    holds_all(Rest).

% update(+Ev)
%   Destructively update the state for a single event Ev.
%
update(Ev) :-
    assertz(Ev),
    findall(Fl, (terminated(Ev, Fl, Cond), holds_all(Cond)), Terms),
    findall(Fl, (initiated(Ev, Fl, Cond), holds_all(Cond)), Inits),
    forall((member(Fl, Terms),state(Fl)), retract(state(Fl))),
    forall((member(Fl, Inits),\+ state(Fl)), assertz(state(Fl))).

% update_all(+Evs)
%   Destructively update the state for a list of events Evs.
%
update_all([]).
update_all([Ev|Evs]) :-
    current_time(Now),
    succ_t(Prev, Now),
    update(happens(Ev, Prev, Now)),
    update_all(Evs).

% generate_id(GoalId)
%
generate_id(GoalId) :-
    random(10000, 100000, RandN),
    ( used(RandN) ->
        geneate_id(GoalId)
    ;
        GoalId = RandN
    ).

% process(+Ri, -NextRi, +Gi, -NextGi)
%   Process reactive rules, both partially resolved from previous cycles Ri and
%   new.
%
%   If the antecedent of any reactive rule is resolved to be empty, then the
%   consequent is added to Gi.
%
process(Ri, NextRi, Gi, NextGi) :-
    ( setof([[HA|TA], C], (reactive_rule([HA|TA], C), query(HA)), Rs)
    ; Rs = []
    ),
    %findall([A,C], reactive_rule(A,C), Rs),
    do_process_new(Rs, NRs, [], NGs),
    do_process_exi(Ri, NRi, Gi, NGi),
    append(NRi, NRs, NextRi),
    append(NGi, NGs, NextGi).

processx(Ri, NextRi, Gi, NextGi) :-
    ( setof([[HA|TA], C], (reactive_rule([HA|TA], C), query(HA)), Rs)
    ; Rs = []
    ),
    do_processx(Rs, NRs, [], NGs),
    do_processx(Ri, NRi, Gi, NGi),
    append(NRi, NRs, NextRi),
    append(NGi, NGs, NextGi).

do_processx([[A, C]|Ris], NewRi, Gi, NewGi) :-
    processx2([A, C], Foo).

/*
processx2([[HA|TA], C], Foo) :-
    findall(, (query(HA),), Rs)
*/

% do_process_new(+Ri, -NRi, +Gi, -NGi)
%   Process a list of all (fresh) reactive rules. Output a partially resolved
%   list of reactive rules NRi and a list of goals NGi.
%
do_process_new([], [], Gi, Gi).

do_process_new([[[], C]|Ris], NewRi, Gi, [goal(GoalId, [C])|NewGi]) :-
    generate_id(GoalId),
    do_process_new(Ris, NewRi, Gi, NewGi).

do_process_new([[A, C]|Ris], NewRi, Gi, NewGi) :-
    %write('A: '),write(A),nl,
    process2(A, NA),!,
    %write('NA: '),write(NA),nl,nl,
    ( NA = [] ->
        generate_id(GoalId),
        NewGi = [goal(GoalId, [C])|NxtGi],
        do_process_new(Ris, NewRi, Gi, NxtGi)
    ; NA = nosusp ->
        do_process_new(Ris, NewRi, Gi, NewGi)
    ; NA = A ->
        do_process_new(Ris, NewRi, Gi, NewGi)
    ;
        NewRi = [[NA, C]|NxtRi],
        do_process_new(Ris, NxtRi, Gi, NewGi)
    ).

%
%
process_priority(Ri, NextRi, Gi, NextGi) :-
    ( setof([[HA|TA], C, P], (reactive_rule([HA|TA], C, P), query(HA)), Rs)
    ; Rs = []
    ),
    do_process_prio_new(Rs, NRs, [], NGs),
    do_process_prio_exi(Ri, NRi, Gi, NGi),
    append(NRi, NRs, NextRi),
    append(NGi, NGs, NextGi).

do_process_prio_new([], [], Gi, Gi).

do_process_prio_new([[[], C, P]|Ris], NewRi, Gi, [goal(P, GoalId, [C])|NewGi]) :-
    generate_id(GoalId),
    do_process_prio_new(Ris, NewRi, Gi, NewGi).

do_process_prio_new([[A, C, P]|Ris], NewRi, Gi, NewGi) :-
    process2(A, NA),!,
    ( NA = [] ->
        generate_id(GoalId),
        NewGi = [goal(P, GoalId, [C])|NxtGi],
        do_process_prio_new(Ris, NewRi, Gi, NxtGi)
    ; NA = nosusp ->
        do_process_prio_new(Ris, NewRi, Gi, NewGi)
    ; NA = A ->
        do_process_prio_new(Ris, NewRi, Gi, NewGi)
    ;
        NewRi = [[NA, C, P]|NxtRi],
        do_process_prio_new(Ris, NxtRi, Gi, NewGi)
    ).

do_process_prio_exi([], [], Gi, Gi).

do_process_prio_exi([[A, C, P]|Ris], NewRi, Gi, NewGi) :-
    process2(A, NA),!,
    ( NA = [] ->
        generate_id(GoalId),
        NewGi = [goal(P, GoalId, [C])|NxtGi],
        do_process_prio_exi(Ris, NewRi, Gi, NxtGi)
    ; NA = nosusp ->
        do_process_prio_exi(Ris, NewRi, Gi, NewGi)
    ;
        NewRi = [[NA, C, P]|NxtRi],
        do_process_prio_exi(Ris, NxtRi, Gi, NewGi)
    ).

% do_process_new(+Ri, -NRi, +Gi, -NGi)
%   Process a list of existing partially resolved reactive rules. Output a
%   partially resolved list of reactive rules NRi and a list of goals NGi.
%
do_process_exi([], [], Gi, Gi).

do_process_exi([[A, C]|Ris], NewRi, Gi, NewGi) :-
    process2(A, NA),!,
    ( NA = [] ->
        generate_id(GoalId),
        NewGi = [goal(GoalId, [C])|NxtGi],
        do_process_exi(Ris, NewRi, Gi, NxtGi)
    ; NA = nosusp ->
        do_process_exi(Ris, NewRi, Gi, NewGi)
    ;
        NewRi = [[NA, C]|NxtRi],
        do_process_exi(Ris, NxtRi, Gi, NewGi)
    ).

% process2(+A, -NA)
%   Resolve an antecedent A according to the operational semantics by querying
%   the augmented state without making temporal constraints false.
%
%   If nothing can be resolved, NA is unified with A.
%   If the antecedent can never be resolved, NA is unified with 'nosusp' to
%   indicate failure.
%
process2([], []).

process2([L|Ls], nosusp) :-
    \+ satisfy_all([L|Ls]).

process2([holds(Fl, T)|Ls], NB) :-
    query(holds(Fl, T)),
    satisfy_all(Ls),
    process2(Ls, NB).

process2([holds(Fl, T)|Ls], [holds(Fl, T)|Ls]) :-
    var(T),
    query(holds(Fl, T)),
    \+ satisfy_all(Ls).

process2([holds(Fl, T)|Ls], nosusp) :-
    number(T), current_time(Now), T == Now,
    query(holds(Fl, T)),
    \+ satisfy_all(Ls).

process2([holds(_, T)|_], nosusp) :-
    number(T), current_time(Now), T < Now.

process2([holds(Fl, T)|_], nosusp) :-
    number(T), current_time(Now), T == Now,
    \+ query(holds(Fl, T)).

process2([holds(Fl, T)|Ls], [holds(Fl, T)|Ls]) :-
    number(T), current_time(Now), T > Now.

process2([happens(Ev, T1, T2)|Ls], NB) :-
    query(happens(Ev, T1, T2)),
    satisfy_all(Ls),
    process2(Ls, NB).

% TODO
process2([happens(Ev, T1, T2)|Ls], [happens(Ev, T1, T2)|Ls]) :-
    (var(T1);var(T2)),
    query(happens(Ev, T1, T2)),
    write('Ls: '),write(Ls),nl,
    \+ satisfy_all(Ls).

process2([happens(Ev, T1, T2)|Ls], nosusp) :-
    (number(T1);number(T2)),
    query(happens(Ev, T1, T2)),
    \+ satisfy_all(Ls).

process2([happens(Ev, T1, T2)|Ls], [happens(Ev, T1, T2)|Ls]) :-
    (var(T1);var(T2)),
    \+ query(happens(Ev, T1, T2)).

process2([happens(_, _, T2)|_], nosusp) :-
    number(T2), current_time(Now), T2 < Now.

process2([happens(Ev, T1, T2)|_], nosusp) :-
    number(T2), current_time(Now), T2 == Now,
    \+ query(happens(Ev, T1, T2)).

process2([happens(Ev, T1, T2)|Ls], [happens(Ev, T1, T2)|Ls]) :-
    number(T2), current_time(Now), T2 > Now.

process2([happens(_, T1, _)|_], nosusp) :-
    number(T1), current_time(Now), T1 < Now.

process2([happens(_, T1, _)|_], nosusp) :-
    number(T1), current_time(Now), T1 == Now.

process2([happens(Ev, T1, T2)|Ls], [happens(Ev, T1, T2)|Ls]) :-
    number(T1), current_time(Now), T1 > Now.

process2([TL|Ls], NB) :-
    l_timeless(TL, _),
    query(TL),
    process2(Ls, NB).

process2([TL|Ls], [TL|Ls]) :-
    l_timeless(TL, _),
    \+ query(TL).

process2([tc(X)|Rest], NB) :-
    ground(X),
    process2(Rest, NB).

% expand_reactive_rules
%   Pre-expand composite events in the antecedents of all reactive rules.
%
expand_reactive_rules() :-
    findall(
        [A, C, EA],
        (
            reactive_rule(A, C),
            expand_antecedent(A, [], EA)
        ),
        NewRRs
    ),
    forall(
        member([A, C, EA], NewRRs),
        (
            ( reactive_rule(A, C) ->
                retract(reactive_rule(A, C))
            ;
                true
            ),
            assertz(reactive_rule(EA, C))
        )
    ).

expand_consequents() :-
    findall(
        [C, EC],
        (
            reactive_rule(_, C),
            expand_consequent(C, [], EC)
        ),
        ECs
    ),
    forall(
        member([C, EC], ECs),
        (
            assertz(expanded_consequent(C, EC))
        )
    ).

/*
expand_reactive_rules(foo) :-
    findall(
        [A, C, EA, EC],
        (
            reactive_rule(A, C),
            expand_antecedent(A, [], EA)
            add_time_consequents
        ),
        NewRRs
    ),
    forall(
        member([A, C, EA], NewRRs),
        (
            ( reactive_rule(A, C) ->
                retract(reactive_rule(A, C))
            ;
                true
            ),
            assertz(reactive_rule(EA, C))
        )
    ).
*/

% expand_antecedent(+A, +Acc, -EA)
%   Expand the antecedent A via backwards reasoning with l_events.
%
expand_antecedent([], EA, EA).
expand_antecedent([happens(E, T1, T2)|As], Acc, EA) :-
    l_events(happens(E, T1, T2), B),
    expand_antecedent(B, [], EB),
    append(Acc, EB, NewAcc),
    expand_antecedent(As, NewAcc, EA).
expand_antecedent([A|As], Acc, EA) :-
    \+ l_events(A, _),
    append(Acc, [A], NewAcc),
    expand_antecedent(As, NewAcc, EA).

% expand_consequent
%
%
expand_consequent([], EC, EC).
expand_consequent([happens(E, T1, T2)|As], Acc, EC) :-
    l_events(happens(E, T1, T2), B),
    expand_consequent(B, [], EB),
    append(Acc, EB, NewAcc),
    expand_consequent(As, NewAcc, EC).
expand_consequent([A|As], Acc, EC) :-
    \+ l_events(A, _),
    append(Acc, [A], NewAcc),
    expand_consequent(As, NewAcc, EC).

% select_actions(+Actions, +Acc, -SelectedActions)
%   Select actions from a list Actions that satisfy all the preconditions in
%   the domain theory.
%
select_actions([], SAs, SAs).
select_actions([ca(_,A)|As], AccA, SAs) :-
    % Pre-conds
    findall(
        NewConds,
        (
            d_pre(Conds), member(A, Conds), select(A, Conds, NewConds)
        ),
        AllConds
    ),
    all_fail(AllConds, Ret),
    % Post-conds
    findall(
        Fl,
        (terminated(A, Fl, Cond), holds_all(Cond)),
        Terms
    ),
    ( Ret = [] ->
        update_action(A),
        append(AccA, [A], NAccA),
        select_actions(As, NAccA, SAs)
    ;
        select_actions(As, AccA, SAs)
    ).

update_action(Ev) :-
    assertz(Ev),
    findall(Fl, (terminated(Ev, Fl, Cond), holds_all(Cond)), Terms),
    findall(Fl, (initiated(Ev, Fl, Cond), holds_all(Cond)), Inits),
    forall((member(Fl, Terms),state(Fl)), retract(state(Fl))),
    forall((member(Fl, Inits),\+ state(Fl)), (assertz(state(Fl)),assertz(this_initiated(Fl)))).

select_actions_concurrent([ca(_,A)|As], AllAs, AccA, SAs) :-
    % Pre-conds
    findall(
        NewConds,
        (
            d_pre(Conds), member(A, Conds), select(A, Conds, NewConds)
        ),
        AllConds
    ),
    all_fail(AllConds, Ret),
    % ConCURRENT
    action_concurrent(A, AllAs),
    ( Ret = [] ->
        update_action(A),
        append(AccA, [A], NAccA),
        select_actions(As, NAccA, SAs)
    ;
        select_actions(As, AccA, SAs)
    ).

action_concurrent(A, AllAs) :-
    findall(Fl, (terminated(A, Fl, Cond), holds_all(Cond)), Terms),
    findall(Fl, (initiated(A, Fl, Cond), holds_all(Cond)), Inits),
    forall(member(Fl, Terms), \+ conflict_init(Fl, AllAs)),
    forall(member(Fl, Inits), \+ conflict_term(Fl, AllAs)).

conflict_init(Fl, []) :- false.
conflict_init(Fl, [ca(_,A)|As]) :-
    findall(Fl2, (initiated(A, Fl2, Cond), holds_all(Cond)), Inits),
    ( member(Fl, Inits) ->
        true
    ;
        conflict_init(Fl, As)
    ).

conflict_term(Fl, []) :- false.
conflict_term(Fl, [ca(_,A)|As]) :-
    findall(Fl2, (terminated(A, Fl2, Cond), holds_all(Cond)), Terms),
    ( member(Fl, Terms) ->
        true
    ;
        conflict_term(Fl, As)
    ).

% all_fail
% TODO
%
all_fail([], []).
all_fail([C|Cs], Ret) :-
    \+ holds_all(C),
    all_fail(Cs, Ret).
all_fail([C|_], failed) :-
    holds_all(C).

resolve_tree_breadth([], NG, NG, CA, CA).
resolve_tree_breadth([goal(GoalId, G)|Gs], AccG, NG, AccA, CA) :-
    retract(current_goal(_)),
    assertz(current_goal(GoalId)),
    write_verbose(['Goal: ',GoalId,nl]),
    resolve_goal_breadth(G, NextGoal, CandActs),
    retractall(tried(GoalId, 0, expanded_consequent(_, _))),
    ( NextGoal = [] ->
        resolve_tree_breadth(Gs, AccG, NG, AccA, CA)
    ;
        append(AccG, [goal(GoalId, NextGoal)], NAccG),
        append(AccA, CandActs, NAccA),
        resolve_tree_breadth(Gs, NAccG, NG, NAccA, CA)
    ).
resolve_tree_breadth_prio([], NG, NG, CA, CA).
resolve_tree_breadth_prio([goal(P, GoalId, G)|Gs], AccG, NG, AccA, CA) :-
    retract(current_goal(_)),
    assertz(current_goal(GoalId)),
    write_verbose(['Goal: ',GoalId,nl]),
    resolve_goal_breadth(G, NextGoal, CandActs),
    retractall(tried(GoalId, 0, expanded_consequent(_, _))),
    ( NextGoal = [] ->
        resolve_tree_breadth_prio(Gs, AccG, NG, AccA, CA)
    ;
        append(AccG, [goal(P, GoalId, NextGoal)], NAccG),
        append(AccA, CandActs, NAccA),
        resolve_tree_breadth_prio(Gs, NAccG, NG, NAccA, CA)
    ).

resolve_goal_breadth([], [], []) :- fail.
resolve_goal_breadth([B1|Bs], NextGoal, CandActs) :-
    \+ satisfy_all(B1),
    ( Bs == [] ->
        write_verbose(['Top-level goal can never be achieved. Dropping.',nl,nl]),
        NextGoal = [],
        CandActs = []
    ;
        write_verbose(['Backtracking.',nl,'0',nl,nl]),
        resolve_goal_breadth(Bs, NextGoal, CandActs)
    ).
resolve_goal_breadth([TLG|[]], NextGoal, CandActs) :-
    copy_term(TLG, TLGC),
    ( tried_all(ec(TLGC)) ->
        clear_tried(ec(TLGC)),
        NextGoal = [TLG],
        CandActs = []
    ; find_unused(ec(TLGC), EC) ->
        assertz(tried(GoalId, 0, expanded_consequent(TLGC, EC))),
        resolve_goal_breadth_end([EC,TLG], NG, CA),
        ( NG == nosusp ->
            resolve_goal_breadth([TLG], NextGoal, CandActs)
        ;
            NextGoal = [NG,TLG],
            CandActs = CA
        )
    ).
resolve_goal_breadth([B1,TLG], NextGoal, CandActs) :-
    ( resolveb(B1, NB, CA) ->
        ( NB == [] ->
            NextGoal = []
        ;
            NextGoal = [NB,TLG] % [] or [happens(...]
        ),
        ( CA == none ->
            CandActs = []
        ;
            CandActs = [CA]
        )
    ;
        resolve_goal_breadth([TLG], NextGoal, CandActs)
    ).
resolve_goal_breadth_end([B1,TLG], NextGoal, CandActs) :-
    ( resolveb(B1, NB, CA) ->
        NextGoal = NB, % [] or [happens(...]
        ( CA == none ->
            CandActs = []
        ;
            CandActs = [CA]
        )
    ;
        NextGoal = nosusp,
        CandActs = none
    ).

resolveb([], [], none).
resolveb([holds(Fl, T)|Rest], NB, CA) :-
    query(holds(Fl, T)), satisfy_all(Rest),
    resolveb(Rest, NB, CA).
resolveb([happens(Ev, T1, T2)|Rest], NB, CA) :-
    query(happens(Ev, T1, T2)), satisfy_all(Rest),
    resolveb(Rest, NB, CA).
resolveb([TL|Rest], NB, CA) :-
    l_timeless(TL, _),
    query(TL),
    resolveb(Rest, NB, CA).
resolveb([tc(X)|Rest], NB, CA) :-
    ground(X),
    resolveb(Rest, NB, CA).
resolveb([happens(Ev, T1, T2)|Rest], NB, CA) :-
    copy_term([happens(Ev, T1, T2)|Rest], [happens(CEv, CT1, CT2)|CLs]),
    try_cand_act([happens(CEv, CT1, CT2)|CLs], CA),
    ( CA \== none ->
        NB = [happens(Ev, T1, T2)|Rest]
    ).
    % CA is none or ca(Earliest, happens)

resolve_tree_threads([goal(GoalId, G)|Gs], NG, CA) :-
    retract(current_goal(_)),
    assertz(current_goal(GoalId)),
    write_verbose(['Goal: ',GoalId,nl]),
    make_threads([goal(GoalId, G)|Gs], ThreadIds, ThreadResults),
    join_threads(ThreadIds),
    merge_results([goal(GoalId, G)|Gs], ThreadResults, [], NG, [], CA).

merge_results([], [], NG, NG, CA, CA).
merge_results([goal(GoalId, G)|Gs], [gt(NextGoal,CandActs)|Rest], AccG, NG, AccA, CA) :-
    append(AccG, [goal(GoalId, NextGoal)], NAccG),
    append(AccA, CandActs, NAccA),
    merge_results(Gs, Rest, NAccG, NG, NAccA, CA).

make_threads([], [], []).
make_threads([goal(GoalId, G)|Gs], [Id|RestIds], [gt(NextGoal,CandActs)|RestGTs]) :-
    thread_create(resolve_goal(G, NextGoal, CandActs), Id),
    make_threads(Gs, RestIds, RestGTs).

join_threads([]).
join_threads([TId|Rest]) :-
    thread_join(TId, _),
    join_threads(Rest).

% resolve_tree
%
resolve_tree([], NG, NG, CA, CA).
resolve_tree([goal(GoalId, G)|Gs], AccG, NG, AccA, CA) :-
    retract(current_goal(_)),
    assertz(current_goal(GoalId)),
    write_verbose(['Goal: ',GoalId,nl]),
    resolve_goal(G, NextGoal, CandActs),
    retractall(failed(GoalId, _, _)),
    retractall(tried(GoalId, _, happens(_,_,_))),
    ( NextGoal = [] ->
        resolve_tree(Gs, AccG, NG, AccA, CA)
    ;
        append(AccG, [goal(GoalId, NextGoal)], NAccG),
        append(AccA, CandActs, NAccA),
        resolve_tree(Gs, NAccG, NG, NAccA, CA)
    ).
resolve_tree_prio([], NG, NG, CA, CA).
resolve_tree_prio([goal(P, GoalId, G)|Gs], AccG, NG, AccA, CA) :-
    retract(current_goal(_)),
    assertz(current_goal(GoalId)),
    write_verbose(['Goal: ',GoalId,nl]),
    resolve_goal(G, NextGoal, CandActs),
    retractall(failed(GoalId, _, _)),
    retractall(tried(GoalId, _, happens(_,_,_))),
    ( NextGoal = [] ->
        resolve_tree_prio(Gs, AccG, NG, AccA, CA)
    ;
        append(AccG, [goal(P, GoalId, NextGoal)], NAccG),
        append(AccA, CandActs, NAccA),
        resolve_tree_prio(Gs, NAccG, NG, NAccA, CA)
    ).

%
%
resolve_goal([], [], []) :- fail.
resolve_goal([B1|Bs], NextGoal, CandActs) :-
    \+ satisfy_all(B1),
    length([B1|Bs], Depth),
    retractall(depth(_)),
    assertz(depth(Depth)),
    write_verbose(['Depth: ',Depth,nl,B1,' has expired.',nl]),
    ( Bs == [] ->
        write_verbose(['Top-level goal can never be achieved. Dropping.',nl,nl]),
        NextGoal = [],
        CandActs = []
    ;
        write_verbose(['Backtracking.',nl,'0',nl,nl]),
        resolve_goal(Bs, NextGoal, CandActs)
    ).
resolve_goal([B1|Bs], NextGoal, CandActs) :-
    length([B1|Bs], Depth),
    retractall(depth(_)),
    assertz(depth(Depth)),
    write_verbose(['Depth: ',Depth,nl]),
    resolve2(B1, NB, EB, CA),
    ( NB == [] ->
        write_verbose(['1',nl,nl]),
        NextGoal = [],
        CandActs = []
    ; NB == cont ->
        write_verbose(['7',nl,nl]),
        ( Bs == [] ->
            NextGoal = [B1],
            CandActs = []
        ;
            resolve_goal(Bs, NextGoal, CandActs)
        )
    ; EB \== [] ->
        write_verbose(['2',nl,nl]),
        resolve_goal([EB,B1|Bs], NextGoal, CandActs)
    ; CA \== none ->
        write_verbose(['3',nl,nl]),
        NextGoal = [NB|Bs],
        CandActs = [CA]
    ; NB == nosusp ->
        write_verbose([B1,nl,Bs,nl]),
        write_verbose(['4',nl,nl]),
        NextGoal = Bs,
        CandActs = []
    ; NB == B1 ->
        write_verbose(['5',nl,nl]),
        NextGoal = [B1|Bs],
        CandActs = []
    ;
        write_verbose(['6',nl,nl]),
        NextGoal = [NB|Bs],
        CandActs = []
    ).

% check_failed
%
check_failed([holds(Fl, T)|Ls], N) :-
    current_goal(GoalId),
    ( failed(GoalId, [holds(Fl, T)|Ls], N1) ->
        N2 is N1 + 1,
        retract(failed(GoalId, [holds(Fl, T)|Ls], N1)),
        assertz(failed(GoalId, [holds(Fl, T)|Ls], N2)),
        N = N1
    ;
        assertz(failed(GoalId, [holds(Fl, T)|Ls], 1)),
        N = 0
    ).
check_failed([happens(Ev, T1, T2)|Ls], N) :-
    current_goal(GoalId),
    ( failed(GoalId, [happens(Ev, T1, T2)|Ls], N1) ->
        N2 is N1 + 1,
        retract(failed(GoalId, [happens(Ev, T1, T2)|Ls], N1)),
        assertz(failed(GoalId, [happens(Ev, T1, T2)|Ls], N2)),
        N = N1
    ;
        assertz(failed(GoalId, [happens(Ev, T1, T2)|Ls], 1)),
        N = 0
    ).

% find_unused
%
find_unused(holds(Fl, T)) :-
    current_goal(GoalId),
    depth(Depth),
    query(holds(Fl, T)),
    \+ tried(GoalId, Depth, state(Fl)).
find_unused(happens(Ev, T1, T2), Body) :-
    current_goal(GoalId),
    depth(Depth),
    l_events(happens(Ev, T1, T2), Body),
    \+ tried(GoalId, Depth, l_events(Ev, Body)).
find_unused(l_tl(TL), Body) :-
    current_goal(GoalId),
    depth(Depth),
    l_timeless(TL, Body),
    \+ tried(GoalId, Depth, l_timeless(TL, Body)).
find_unused(ec(C), EC) :-
    current_goal(GoalId),
    expanded_consequent(C, EC),
    \+ tried(GoalId, 0, expanded_consequent(C, EC)).

% tried_all
%
tried_all(holds(Fl, T)) :-
    current_goal(GoalId),
    depth(Depth),
    forall(
        query(holds(Fl, T)),
        ( 
            tried(GoalId, Depth, state(Fl))
        )
    ).
tried_all(happens(Ev, T1, T2)) :-
    current_goal(GoalId),
    depth(Depth),
    forall(
        l_events(happens(Ev, T1, T2), B),
        (
            tried(GoalId, Depth, l_events(Ev, B))
        )
    ).
tried_all(l_tl(TL)) :-
    current_goal(GoalId),
    depth(Depth),
    forall(
        l_timeless(TL, B),
        (
            tried(GoalId, Depth, l_timeless(TL, B))
        )
    ).
tried_all(ec(C)) :-
    current_goal(GoalId),
    forall(
        expanded_consequent(C, EC),
        (
            tried(GoalId, 0, expanded_consequent(C, EC))
        )
    ).

% clear_tried
%
clear_tried(holds(Fl, _)) :-
    current_goal(GoalId),
    depth(Depth),
    retractall(tried(GoalId, Depth, state(Fl))).
clear_tried(l_events(Ev, _)) :-
    current_goal(GoalId),
    depth(Depth),
    retractall(tried(GoalId, Depth, l_events(Ev, _))).
clear_tried(happens(Ev, _, _)) :-
    current_goal(GoalId),
    depth(Depth),
    retractall(tried(GoalId, Depth, happens(Ev, _, _))).
clear_tried(l_tl(TL)) :-
    current_goal(GoalId),
    depth(Depth),
    retractall(tried(GoalId, Depth, l_timeless(TL, _))).
clear_tried(ec(C)) :-
    current_goal(GoalId),
    retractall(tried(GoalId, 0, expanded_consequent(C, _))).

% clear_failed
%
clear_failed(B) :-
    current_goal(GoalId),
    forall(
        failed(GoalId, B, _),
        retract(failed(GoalId, B, _))
    ).

% resolve
%
resolve2([L|Ls], [L|Ls], [], none) :-
    steps(0).
resolve2([holds(Fl, T)|Ls], NB, EB, CA) :-
    (
        resolve2_holds([holds(Fl, T)|Ls], NB, EB, CA)
    ;
        check_failed([holds(Fl, T)|Ls], N),
        /*
        write('Failed '),write(Fl),write(' '),write(N),write(' times.'),nl,
        write('Backtracking NOW.'),nl,
        NB = cont,
        EB = [],
        CA = none
        */
        ( N == 0 ->
            NB = cont,
            EB = [],
            CA = none
        ;
            write('Failed to resolve branch ['),write(holds(Fl)),
            write(', ...].'),nl,
            write('Backtracking next cycle.'),nl,
            clear_failed([holds(Fl, T)|Ls]),
            %current_goal(GoalId),
            %findall(X, failed(GoalId, X, _), Foo),
            %nl,nl,write(Foo),nl,nl,
            NB = nosusp,
            EB = [],
            CA = none
        )
    ).
resolve2([happens(Ev, T1, T2)|Ls], NB, EB, CA) :-
    l_events(happens(Ev, T1, T2), _),
    /*
    l_events(CEH, CEB),
    unifiable(CEH, happens(Ev, T1, T2), _),
    */
    ( tried_all(happens(Ev, T1, T2)) ->
        write_verbose(['All possible unifications for ',Ev,' failed',nl,'Backtracking.',nl]),
        clear_tried(l_events(Ev, _)),
        NB = cont,
        EB = [],
        CA = none
    ; find_unused(happens(Ev, T1, T2), Body) ->
        write_verbose(['Bound composite event ',Ev,' to',nl,Body,nl]),
        current_goal(GoalId),
        depth(Depth),
        assertz(tried(GoalId, Depth, l_events(Ev, Body))),
        /*
        findall(X, tried(GoalId, Depth, l_events(Ev, X)), Foo),
        write(Foo),nl,
        */
        NB = [happens(Ev, T1, T2)|Ls],
        append(Body, Ls, EB),
        CA = none
    ;
        write('ERROR: Nothing worked!'),nl
    ).
    /*
    % umm...
    % TODO this needs to be checked and cleared when it all fails...
    % need to remember which l_events have been explored, ACROSS cycles
    current_goal(GoalId),
    depth(Depth),
    assertz(tried(GoalId, Depth, l_events(CEH, CEB))),
    append(B, Ls, EB),
    reduce_step.
    */
resolve2([happens(Ev, T1, T2)|Ls], NB, EB, CA) :-
    \+ l_events(happens(Ev, _, _), _),
    (
        resolve2_happens([happens(Ev, T1, T2)|Ls], NB, EB, CA)
    ;
        check_failed([happens(Ev, T1, T2)|Ls], N),
        %write('Failed '),write(happens(Ev)),write(' '),write(N),write(' times.'),nl,
        % TODO let user specify this?
        ( N =< 5 ->
            NB = [happens(Ev, T1, T2)|Ls],
            EB = [],
            copy_term([happens(Ev, T1, T2)|Ls], [happens(CEv, CT1, CT2)|CLs]),
            try_cand_act([happens(CEv, CT1, CT2)|CLs], CA)
        ;
            write('Failed to resolve branch ['),write(happens(Ev)),
            write(', ...].'),nl,
            write('Backtracking next cycle.'),nl,
            clear_failed([happens(Ev, T1, T2)|Ls]),
            /*
            current_goal(GoalId),
            findall(X, failed(GoalId, X, _), Foo),
            nl,nl,write(Foo),nl,nl,
            */
            NB = nosusp,
            EB = [],
            CA = none
        )
    ).

% TODO
% if Fl in holds(Fl, T) is ground, then there's no need to actually create a
% new branch!

% resolve2_holds
%
resolve2_holds([holds(Fl, T)|Ls], cont, [], none) :-
    number(T), current_time(Now), T == Now,
    copy_term([holds(Fl, T)|Ls], [holds(CFl, CT)|CLs]),
    query(holds(CFl, CT)),
    \+ satisfy_all(CLs),
    write_verbose([holds(Fl, T),' but time constraints cannot be satisfied.',nl,'Backtracking.',nl]),
    reduce_step.

resolve2_holds([holds(Fl, T)|_], cont, [], none) :-
    number(T), current_time(Now), T == Now,
    copy_term(holds(Fl, T), holds(CFl, CT)),
    \+ query(holds(CFl, CT)),
    write_verbose([holds(Fl, T),' does not hold.',nl,'Backtracking.',nl]),
    reduce_step.

resolve2_holds([holds(_, T)|_], cont, [], none) :-
    number(T), current_time(Now), T < Now,
    write_verbose([holds(Fl, T),' was in the past!',nl,'Backtracking',nl]),
    reduce_step.

resolve2_holds([holds(Fl, T)|Ls], NB, EB, CA) :-
    %(var(T); (number(T), current_time(Now), T > Now)),
    copy_term(holds(Fl, T), holds(TFl, TT)),
    query(holds(TFl, TT)),
    copy_term([holds(Fl, T)|Ls], [holds(CFl, CT)|CLs]),
    ( tried_all(holds(CFl, CT)) ->
        write_verbose(['All possible unifications for ',holds(Fl),' failed.',nl,'Backtracking.',nl]),
        % TODO 22 Aug 17:42
        clear_tried(holds(Fl, T)),
        NB = cont,
        EB = [],
        CA = none
    ; find_unused(holds(CFl, CT)) ->
        satisfy_all(CLs),
        reduce_step,
        resolve2_same(CT, CLs, EB),
        write_verbose(['Bound fluent ',holds(Fl),' to ',holds(CFl),nl]),
        current_goal(GoalId),
        depth(Depth),
        assertz(tried(GoalId, Depth, state(CFl))),
        ( EB = [] ->
            NB = []
        ;%EB \= [] ->
            % it doesn't actually matter what NB is, just can't be unbound, or []
            NB = [holds(Fl, T)|Ls]
        )
    ).
    /*
    query(holds(CFl, CT)),
    */
    % check for ground here
    % so when we get here, Fl has become bound, need to track this ACROSS
    % cycles
    /*
    ( ground(Fl) ->
        ( EB = [] ->
            NB = []
        ;%EB \= [] ->
            NB = cont
        )
    */

% the only way for resolve2_same to succeed is for it to resolve all OR it
% returns some kind of happens(Act, T1, T2) where T1 is bound to Now.
%
% fluents that must hold in the same cycle as other fluents are expected to be
% written together.
%
% fluents that must hold in the same cycle as a certain action are expected to
% be written together.
%
resolve2_same(_, [], []).

resolve2_same(T1, [tc(X)|Ls], Ret) :-
    ground(X),
    resolve2_same(T1, Ls, Ret).

resolve2_same(_, [L|Ls], [L|Ls]) :-
    L \= holds(_, _).

resolve2_same(_, [holds(Fl, T)|Ls], [holds(Fl, T)|Ls]) :-
    var(T).

resolve2_same(T1, [holds(Fl, T2)|Ls], Ret) :-
    number(T2),
    ( T1 =:= T2 ->
        ( query(holds(Fl, T2)), satisfy_all(Ls) ->
            resolve2_same(T1, Ls, Ret)
        ;
            fail
        )
    ;
        Ret = [holds(Fl, T2)|Ls]
    ).

/*
resolve2_happens([happens(Ev, T1, T2)|Ls], cont, [], none) :-
    check_failed([happens(Ev, T1, T2)|Ls], N),
    write('hai: '),write(N),nl,
    reduce_step.
*/

% XXX 29 Aug 09:35 - Changed the nosusp to cont
resolve2_happens([happens(Ev, T1, T2)|Ls], cont, [], none) :-
    (number(T1);number(T2)),
    copy_term([happens(Ev, T1, T2)|Ls], [happens(CEv, CT1, CT2)|CLs]),
    query(happens(CEv, CT1, CT2)),
    \+ satisfy_all(CLs),
    reduce_step.

% TODO 22 Aug 18:11 Test
resolve2_happens([happens(Ev, T1, T2)|Ls], cont, [], none) :-
    number(T1), current_time(Now), Prev is Now - 1, T1 = Prev,
    copy_term([happens(Ev, T1, T2)|Ls], [happens(CEv, CT1, CT2)|CLs]),
    \+ query(happens(CEv, CT1, CT2)),
    write_verbose([happens(Ev, T1, T2),' did not happen!',nl,'Backtracking.',nl]),
    reduce_step.

resolve2_happens([happens(_, _, T2)|_], cont, [], none) :-
    number(T2), current_time(Now), T2 < Now,
    reduce_step.

resolve2_happens([happens(Ev, T1, T2)|_], cont, [], none) :-
    number(T2), current_time(Now), T2 == Now,
    copy_term(happens(Ev, T1, T2), happens(CEv, CT1, CT2)),
    \+ query(happens(CEv, CT1, CT2)),
    reduce_step.

resolve2_happens([happens(_, T1, _)|_], cont, [], none) :-
    number(T1), current_time(Now), Prev is Now - 1, T1 < Prev,
    reduce_step.

resolve2_happens([happens(Ev, T1, T2)|Ls], NB, EB, CA) :-
    number(T1), current_time(Now), T1 == Now,
    copy_term([happens(Ev, T1, T2)|Ls], [happens(CEv, CT1, CT2)|CLs]),
    % XXX 22 Aug 18:34 IF CA IS NULL --> then implies that PRECONDS FAILED
    % NEED to BACKTRACK here!!!11 -- DONE
    try_cand_act([happens(CEv, CT1, CT2)|CLs], CA),
    ( CA = none ->
        write_verbose(['Special1! Backtracking.',nl]),
        NB = cont,
        EB = []
    ;
        NB = [happens(Ev, T1, T2)|Ls],
        EB = []
    ),
    reduce_step.

resolve2_happens([happens(Ev, T1, T2)|Ls], NB, EB, CA) :-
    copy_term([happens(Ev, T1, T2)|Ls], [happens(CEv, CT1, CT2)|CLs]),
    current_goal(GoalId),
    depth(Depth),
    query(happens(CEv, CT1, CT2)),
    ( \+ tried(GoalId, Depth, happens(CEv, CT1, CT2)) ->
        satisfy_all(CLs),
        reduce_step,
        resolve2_same(CT2, CLs, EB),
        assertz(tried(GoalId, Depth, happens(Ev, T1, T2))),
        ( EB = [] ->
            NB = []
        ;%EB \= [] ->
            % doesn't matter what NB is
            % XXX 22 Aug 19:31 When the happens(Ev) binds, remove it from the
            % state! Only let it do this once.
            %retract(happens(Ev, _, _)),
            NB = [happens(Ev, T1, T2)|Ls]
        )
    ;
        clear_tried(happens(CEv, CT1, CT2)),
        % XXX 25 Aug 15:27
        % It happened, it failed, see if it can be done again next cycle.
        copy_term([happens(Ev, T1, T2)|Ls], [happens(AEv, AT1, AT2)|ALs]),
        try_cand_act([happens(AEv, AT1, AT2)|ALs], CA),
        ( CA = none ->
            write_verbose(['Special2! Backtracking.',nl]),
            NB = cont,
            EB = []
        ;
            NB = [happens(Ev, T1, T2)|Ls],
            EB = []
        )
        /*
        NB = cont,
        EB = [],
        write('aip'),nl,
        write('Backtracking NOW.'),nl
        */
    ).

resolve2([TL|Ls], NB, EB, CA) :-
    l_timeless(TL, _),
    (
        resolve2_timeless([TL|Ls], NB, EB, CA)
    ;
        % derp, l_timeless(TL) failed
        % TODO 29 Aug 08:48 - Should l_timeless be kept and retried ACROSS cycles?
        write_verbose([l_timeless(TL),' failed.',nl,'Backtracking.',nl]),
        NB = cont,
        EB = [],
        CA = none
    ).

resolve2_timeless([TL|Ls], NB, EB, CA) :-
    copy_term([TL|Ls], [CTL|CLs]),
    ( tried_all(l_tl(CTL)) ->
        write_verbose(['All possible unifications for ',l_timeless(TL),' failed.',nl,'Backtracking.',nl]),
        clear_tried(l_tl(TL)),
        NB = cont,
        EB = [],
        CA = none
    ; find_unused(l_tl(CTL), Body) ->
        satisfy_all(CLs),
        reduce_step,
        query(CTL),
        write_verbose(['Calculated ',TL,' to ',CTL,nl]),
        current_goal(GoalId),
        depth(Depth),
        assertz(tried(GoalId, Depth, l_timeless(TL, Body))),
        NB = [TL|Ls],
        EB = CLs,
        CA = none
    ).

/*
% s
resolve2([TL|Ls], [TL|Ls], [], none) :-
    l_timeless(TL, _),
    copy_term([TL|Ls], [CTL|_]),
    \+ query(CTL),
    reduce_step.
*/

% Simplify time constraints
resolve2([tc(X)|Rest], NB, EB, CA) :-
    ground(X),
    resolve2(Rest, NB, EB, CA).

resolve2([], [], [], none).

%
%
try_cand_act([happens(Ev, T1, T2)|Bs], CA) :-
    (
        action(Ev),
        current_time(T1), T2 is T1 + 1,
        satisfy_all(Bs),
        T3 is T1 - 1,
        findall(
            NewConds,
            (
                d_pre(Conds),
                member(happens(Ev, T1, T2), Conds),
                select(happens(Ev, T1, T2), Conds, NewConds)
            ),
            AllConds
        ),
        all_fail(AllConds, [])
    ->
        find_deadline(Bs, Deadlines),sort(Deadlines, Sorted),
        ( Sorted = [Earliest|_] ->
            true
        ;
            Earliest = 9999999999999999999
        ),
        CA = ca(Earliest, happens(Ev, T1, T2)),
        write_verbose(['Adding candidate action ',Ev,'.',nl])
    ;
        CA = none,
        write_verbose(['Could not add action ',Ev,' to candidate actions.',nl])
    ).

find_deadline([], []).

find_deadline([tc(<(X,Y))|T], [Z|Res]) :-
    \+ no_vars(X), no_vars(Y),
    bind_vars(X),
    #=(X,Z),
    #<(Z,Y),
    labeling([max(Z)], [Z]),
    find_deadline(T, Res).

/*
find_deadline([tc(<(X,Y))|T], [Z|Res]) :-
    no_vars(X), no_vars(Y),
    parse(X, RX),
    parse(Y, RY),
    Z is Y - X - 1,
    find_deadline(T, Res).
*/

find_deadline([tc(=<(X,Y))|T], [Z|Res]) :-
    \+ no_vars(X), no_vars(Y),
    bind_vars(X),
    #=(X,Z),
    #=<(Z,Y),
    labeling([max(Z)], [Z]),
    find_deadline(T, Res).

/*
find_deadline([tc(=<(X,Y))|T], [Z|Res]) :-
    no_vars(X), no_vars(Y),
    parse(X, RX),
    parse(Y, RY),
    Z is Y - X,
    find_deadline(T, Res).
*/

find_deadline([H|T], Res) :-
    find_deadline(T, Res).

%
%
reduce_step() :-
    steps(C),
    NC is C-1,
    retract(steps(C)),
    assertz(steps(NC)).

% satisfy_all(+L)
%
satisfy_all([]).

satisfy_all([tc(X)|Rest]) :-
    copy_term(X, XC),
    satisfy(XC),
    %write(XC),nl,
    satisfy_all(Rest).

satisfy_all([Y|Rest]) :-
    Y \= tc(_),
    satisfy_all(Rest).

% satisfy_upper
%
satisfy_upper(L) :-
    copy_term(L, LC),
    do_satisfy_upper(LC).

%
%
do_satisfy_upper([]).

do_satisfy_upper([tc(<(X,Y))|Rest]) :-
    var(X), no_vars(Y),
    current_time(Now),
    current_prolog_flag(max_integer, Max),
    in(X, ..(Now,Max)),
    #<(X, Y),
    do_satisfy_upper(Rest).

do_satisfy_upper([tc(<(X,Y))|Rest]) :-
    no_vars(X), var(Y),
    current_time(Now),
    current_prolog_flag(max_integer, Max),
    in(Y, ..(Now,Max)),
    #<(X, Y),
    do_satisfy_upper(Rest).

do_satisfy_upper([tc(<(X,Y))|Rest]) :-
    var(X), var(Y),
    do_satisfy_upper(Rest).

do_satisfy_upper([tc(<(X,Y))|Rest]) :-
    no_vars(X), no_vars(Y),
    parse(X, RX), parse(Y, RY),
    RX < RY,
    do_satisfy_upper(Rest).

do_satisfy_upper([tc(=<(X,Y))|Rest]) :-
    var(X), no_vars(Y),
    current_time(Now),
    current_prolog_flag(max_integer, Max),
    in(X, ..(Now,Max)),
    #=<(X, Y),
    do_satisfy_upper(Rest).

do_satisfy_upper([tc(=<(X,Y))|Rest]) :-
    no_vars(X), var(Y),
    current_time(Now),
    current_prolog_flag(max_integer, Max),
    in(Y, ..(Now,Max)),
    #=<(X, Y),
    do_satisfy_upper(Rest).

do_satisfy_upper([tc(=<(X,Y))|Rest]) :-
    var(X), var(Y),
    do_satisfy_upper(Rest).

do_satisfy_upper([tc(=<(X,Y))|Rest]) :-
    no_vars(X), no_vars(Y),
    parse(X, RX), parse(Y, RY),
    RX =< RY,
    do_satisfy_upper(Rest).

do_satisfy_upper([H|Rest]) :-
    H \= tc(_),
    do_satisfy_upper(Rest).

%
%
no_vars(Exp) :-
    nonvar(Exp),
    Exp =.. L,
    check_vars(L).

%
%
check_vars([]).

check_vars([H|T]) :-
    compound(H),
    H =.. L,
    check_vars(L),
    check_vars(T).

check_vars([H|T]) :-
    atomic(H),
    check_vars(T).

check_vars([H|_]) :-
    var(H),
    fail.

bind_vars(Exp) :-
    var(Exp),
    current_time(Now),
    current_prolog_flag(max_integer, Max),
    in(Exp, ..(Now,Max)).

bind_vars(Exp) :-
    nonvar(Exp),
    Exp =.. L,
    do_bind_vars(L).

do_bind_vars([]).

do_bind_vars([H|T]) :-
    compound(H),
    H =.. L,
    do_bind_vars(L),
    do_bind_vars(T).

do_bind_vars([H|T]) :-
    atomic(H),
    do_bind_vars(T).

do_bind_vars([H|T]) :-
    var(H),
    current_time(Now),
    current_prolog_flag(max_integer, Max),
    in(H, ..(Now,Max)),
    do_bind_vars(T).


%
%
parse(Exp, Res) :-
    ( number(Exp) ->
        Res = Exp
    ; Exp = (L + R) ->
        parse(L, RL),
        parse(R, RR),
        Res is RL + RR
    ; Exp = (L - R) ->
        parse(L, RL),
        parse(R, RR),
        Res is RL - RR
    ; Exp = (L * R) ->
        parse(L, RL),
        parse(R, RR),
        Res is L * R
    ; Exp = (L / R) ->
        parse(L, RL),
        parse(R, RR),
        Res is L / R
    ; Exp = abs(E) ->
        parse(E, RE),
        Res is abs(RE)
    ).

%
%
satisfy(<(X,Y)) :-
    \+ no_vars(X), no_vars(Y),
    bind_vars(X),
    #<(X, Y).

satisfy(<(X,Y)) :-
    no_vars(X), \+ no_vars(Y),
    bind_vars(Y),
    #<(X, Y).

satisfy(<(X,Y)) :-
    \+ no_vars(X), \+ no_vars(Y).

satisfy(<(X,Y)) :-
    no_vars(X), no_vars(Y),
    parse(X, RX), parse(Y, RY),
    RX < RY.

satisfy(=<(X,Y)) :-
    \+ no_vars(X), no_vars(Y),
    bind_vars(X),
    #=<(X, Y).

satisfy(=<(X,Y)) :-
    no_vars(X), \+ no_vars(Y),
    bind_vars(Y),
    #=<(X, Y).

satisfy(=<(X,Y)) :-
    \+ no_vars(X),
    \+ no_vars(Y).

satisfy(=<(X,Y)) :-
    no_vars(X), no_vars(Y),
    parse(X, RX), parse(Y, RY),
    RX =< RY.

% check_syntax
%
check_syntax() :-
    forall(reactive_rule(A, C), (
        check_reactive_rule(A, RA),
        (RA = no -> fail ; true),
        check_reactive_rule(C, RC),
        (RC = no -> fail ; true)
    )),
    forall(l_int(P, B), (
        (P @= holds(_,_) ->
            true
        ;
            write('SYNTAX ERROR: '),
            write('``'),write(P),write(''''''),
            write(' is not a valid intensional predicate.'),nl,
            fail
        ),
        check_lp_int(B, RB),
        (RB = no -> fail ; true)
    )),
    forall(l_events(P, B), (
        (P @= happens(_,_,_) ->
            true
        ;
            write('SYNTAX ERROR: '),
            write('``'),write(P),write(''''''),
            write(' is not a valid composite event predicate.'),nl,
            fail
        ),
        check_lp_events(B, RB),
        (RB = no -> fail ; true)
    )),
    forall(d_pre(B), (
        check_d_pre(B, RB),
        (RB = no -> fail ; true)
    )),
    forall(initiated(Ev, Fl, Cond), (
        (Ev @= happens(Ev2, _, _) ->
            (d_event(Ev2) ->
                true
            ;
                write('SYNTAX ERROR: '),
                write('``'),write(Ev2),write(''''''),
                write(' must be a simple event (event/action) predicate.'),nl,
                fail
            )
        ;
            write('SYNTAX ERROR: '),
            write('``'),write(Ev),write(''''''),
            write(' is not a valid domain post-condition predicate.'),nl,
            fail
        ),
        (d_head(Fl) ->
            true
        ;
            write('SYNTAX ERROR: '),
            write('``'),write(Fl),write(''''''),
            write(' must be an extensional fluent predicate.'),nl,
            fail
        ),
        check_d_post(B, RB),
        (RB = no -> fail ; true)
    )),
    forall(terminated(Ev, Fl, Cond), (
        (Ev @= happens(Ev2, _, _) ->
            (d_event(Ev2) ->
                true
            ;
                write('SYNTAX ERROR: '),
                write('``'),write(Ev2),write(''''''),
                write(' must be a simple event (event/action) predicate.'),nl,
                fail
            )
        ;
            write('SYNTAX ERROR: '),
            write('``'),write(Ev),write(''''''),
            write(' is not a valid domain post-condition predicate.'),nl,
            fail
        ),
        (d_head(Fl) ->
            true
        ;
            write('SYNTAX ERROR: '),
            write('``'),write(Fl),write(''''''),
            write(' must be an extensional fluent predicate.'),nl,
            fail
        ),
        check_d_post(B, RB),
        (RB = no -> fail ; true)
    )).

check_reactive_rule([], []).
check_reactive_rule([H|T], NT) :-
    reactive_conjunct(H),
    check_reactive_rule(T, NT).
check_reactive_rule([H|_], no) :-
    \+ reactive_conjunct(H),
    write('SYNTAX ERROR: '),
    write('``'),write(H),write(''''''),
    write(' is not a valid reactive rule conjunct.'),nl.

check_lp_int([], []).
check_lp_int([H|T], NT) :-
    l_int_body(H),
    check_lp_int(T, NT).
check_lp_int([H|_], no) :-
    \+ l_int_body(H),
    write('SYNTAX ERROR: '),
    write('``'),write(H),write(''''''),
    write(' is not a valid L_int body.'),nl.

check_lp_events([], []).
check_lp_events([H|T], NT) :-
    l_events_body(H),
    check_lp_events(T, NT).
check_lp_events([H|_], no) :-
    \+ l_events_body(H),
    write('SYNTAX ERROR: '),
    write('``'),write(H),write(''''''),
    write(' is not a valid L_events body.'),nl.

check_d_pre([], []).
check_d_pre([H|T], NT) :-
    d_body(H),
    check_d_pre(T, NT).
check_d_pre([H|_], no) :-
    \+ d_body(H),
    write('SYNTAX ERROR: '),
    write('``'),write(H),write(''''''),
    write(' is not a valid D_pre body.'),nl.

check_d_post([], []).
check_d_post([H|T], NT) :-
    d_body(H),
    check_d_post(T, NT).
check_d_post([H|_], no) :-
    \+ d_body(H),
    write('SYNTAX ERROR: '),
    write('``'),write(H),write(''''''),
    write(' is not a valid D_post body.'),nl.

% assert_list
%
assert_list([]).

assert_list([H|T]) :-
    assertz(state(H)),
    assert_list(T).

%
%
pprint_goal([]).

pprint_goal([goal(_, [H|_])|Rest]) :-
    write(H),nl,
    pprint_goal(Rest).

pprint_goal([goal(_, _, [H|_])|Rest]) :-
    write(H),nl,
    pprint_goal(Rest).

% next_time()
%   Succeeds to the next time point. Destructively updates current_time/1 and
%   succ_t/2.
%
next_time() :-
    current_time(This),
    retract(current_time(This)),
    Next is This + 1,
    assertz(current_time(Next)),
    assertz(succ_t(This, Next)),
    retract(steps(_)),
    assertz(steps(1000)).

% go(+File)
%
go(File) :-
    datime_setrand,
    load_dyn(File),
    check_syntax,
    initial_state(IS), assert_list(IS),
    %check_syntax,
    expand_reactive_rules,
    assertz(current_time(1)),
    assertz(succ_t(0, 1)),
    assertz(steps(1000)),
    assertz(current_goal(0)),
    assertz(depth(0)),
    (cycle([], [], []); cleanup).

go(File, OptionsList) :-
    parse_options(OptionsList),
    datime_setrand,
    load_dyn(File),
    check_syntax,
    initial_state(IS), assert_list(IS),
    expand_reactive_rules,
    ( option(breadth) ->
        expand_consequents
    ;
        true
    ),
    assertz(current_time(1)),
    assertz(succ_t(0, 1)),
    assertz(steps(1000)),
    assertz(current_goal(0)),
    assertz(depth(0)),
    (cycle_options([], [], []); cleanup).

read_obs(Obs) :-
    read(user_input, Obs),
    ( \+ is_list(Obs) ->
        write(user_error, 'ERROR: Input must be a proper list.'),nl,
        read_obs(Obs)
    ;
        true
    ).

%
%
parse_options([]).
parse_options([manual|Rest]) :-
    assertz(option(manual)),
    parse_options(Rest).
parse_options([verbose|Rest]) :-
    assertz(option(verbose)),
    parse_options(Rest).
parse_options([goal_strat(breadth)|Rest]) :-
    assertz(option(breadth)),
    parse_options(Rest).
parse_options([goal_strat(depth)|Rest]) :-
    parse_options(Rest).
parse_options([priority|Rest]) :-
    assertz(option(priority)),
    parse_options(Rest).
parse_options([_|Rest]) :-
    parse_options(Rest).

write_verbose(What) :-
    ( option(verbose) ->
        do_write(What)
    ;
        true
    ).

do_write([]).

do_write([pprint_goal(What)|Rest]) :- !,
    pprint_goal(What),
    do_write(Rest).

do_write([nl|Rest]) :- !,
    nl,
    do_write(Rest).

do_write([What|Rest]) :- !,
    write(What),
    do_write(Rest).

pick_highest_tier(NGi_P, NGi, RGi) :-
    sort(NGi_P, NGi_P_sorted),
    reverse(NGi_P_sorted, [goal(P, GoalId, G)|OtherGoals]),
    Lower is (P // 10) * 10,
    pick_highest_tier2(Lower, [goal(P, GoalId, G)|OtherGoals], NGi, RGi).

pick_highest_tier2(_, [], [], []).

pick_highest_tier2(Lower, [goal(P, GoalId, G)|OtherGoals], [goal(P, GoalId, G)|NGi], RGi) :-
    P >= Lower,
    pick_highest_tier2(Lower, OtherGoals, NGi, RGi).

pick_highest_tier2(Lower, [goal(P, GoalId, G)|OtherGoals], [], [goal(P, GoalId, G)|OtherGoals]) :-
    P < Lower.

% cleanup
%
cleanup :-
    retractall(action(_)),
    retractall(cacts(_)),
    retractall(current_goal(_)),
    retractall(current_time(_)),
    retractall(d_pre(_)),
    retractall(depth(_)),
    retractall(event(_)),
    retractall(expanded_consequent(_,_)),
    retractall(failed(_, _, _)),
    retractall(fluent(_)),
    retractall(happens(_, _, _)),
    retractall(initiated(_, _, _)),
    retractall(l_events(_, _)),
    retractall(l_int(_, _)),
    retractall(l_timeless(_, _)),
    retractall(observe(_, _)),
    retractall(option(_)),
    retractall(reactive_rule(_, _)),
    retractall(state(_)),
    retractall(steps(_)),
    retractall(succ_t(_, _)),
    retractall(susp(_)),
    retractall(terminated(_, _, _)),
    retractall(tried(_, _, _)),
    retractall(used(_)),
    retractall(this_initiated(_)).

cycle(CAi, Ri, Gi) :-
    current_time(Time),
    retractall(happens(_, _, _)),
    nl,
    write('===================='),nl,
    write('Cycle '),write(Time),nl,
    write('===================='),nl,nl,
    %datime(Date),
    %write(Date),nl,
    %write('Partial reactive rules:'),nl,write(Ri),nl,nl,
    write('Candidate actions:'),nl,write(CAi),nl,nl,
    sort(CAi, SortedCAi),
    select_actions(SortedCAi, [], Actions),
    write('Selected actions:'),nl,write(Actions),nl,nl,
    observe(Observations, Time),
    write('Observations:'),nl,write(Observations),nl,nl,
    update_all(Observations),
    findall(Fl, state(Fl), State),
    write('Database state:'),nl,write(State),nl,nl,
    process(Ri, NRi, Gi, NGi),
    write('New partial reactive rules:'),nl,write(NRi),nl,nl,
    write('New goals:'),nl,pprint_goal(NGi),nl,
    write('********************'),nl,nl,
    resolve_tree_breadth(NGi, [], NextGi, [], CA),
    write('********************'),nl,nl,
    ( NextGi = [] ->
        write('Resolved goals:'),nl,write(NextGi),nl
    ;
        write('Resolved goals:'),nl,pprint_goal(NextGi)
    ),
    !,
    next_time,
    cycle(CA, NRi, NextGi).

cycle_options(CAi, Ri, Gi) :-
    current_time(Time),
    retractall(happens(_, _, _)),
    nl,
    write_verbose(['====================',nl]),
    write('* Cycle '),write(Time),write(' *'),nl,
    write_verbose(['====================',nl,nl]),
    write_verbose(['Candidate actions:',nl,CAi,nl,nl]),
    sort(CAi, SortedCAi),
    select_actions(SortedCAi, [], Actions),
    retractall(this_initiated(_)),
    write_verbose(['Selected actions:',nl,Actions,nl,nl]),
    ( option(manual) ->
        read_obs(Observations)
    ;
        observe(Observations, Time)
    ),
    write_verbose(['Observations:',nl,Observations,nl,nl]),
    update_all(Observations),
    findall(Fl, state(Fl), State),
    write_verbose(['Database state:',nl,State,nl,nl]),
    ( option(priority) ->
        process_priority(Ri, NRi, Gi, NGi_P)
    ;
        process(Ri, NRi, Gi, NGi)
    ),!,
    ( option(priority) ->
        pick_highest_tier(NGi_P, NGi, RGi)
    ;
        true
    ),
    write_verbose(['New partial reactive rules:',nl,NRi,nl,nl]),
    write_verbose(['New goals:',nl,pprint_goal(NGi),nl]),
    ( option(priority) ->
        ( option(breadth) ->
            resolve_tree_breadth_prio(NGi, [], NewGi, [], CA)
        ;
            resolve_tree_prio(NGi, [], NewGi, [], CA)
        ),
        append(NewGi, RGi, NextGi)
    ;
        ( option(breadth) ->
            resolve_tree_breadth(NGi, [], NextGi, [], CA)
        ;
            resolve_tree(NGi, [], NextGi, [], CA)
        )
    ),
    ( NextGi = [] ->
        write('Resolved goals:'),nl,write(NextGi),nl
    ;
        write('Resolved goals:'),nl,pprint_goal(NextGi),nl
    ),
    !,
    next_time,
    cycle_options(CA, NRi, NextGi).
