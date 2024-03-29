%%
:- export fluent_pred/1, event_pred/1, temp_constraint/1, reactive_conjunct/1.
:- export l_int_body/1, l_events_body/1, d_head/1, d_event/1, d_body/1.

:- import action/1, cacts/1, current_time/1, d_pre/1, event/1 from usermod.
:- import fluent/1, happens/3, initiated/3, l_events/2, l_int/2 from usermod.
:- import l_timeless/2, observe/2, reactive_rule/2, state/1 from usermod.
:- import succ_t/2, susp/1, terminated/3 from usermod.


% fluent_pred(+Fl)
%   True if Fl is a fluent predicate symbol.
%
fluent_pred(Fl) :-
    % Extensional predicates, represent facts in the state S_i.
    fluent(Fl).
fluent_pred(not(Fl)) :-
    fluent(Fl).
fluent_pred(Fl) :-
    % Intensional predicates, defined in L_int.
    l_int(holds(Fl, _), _).
fluent_pred(not(Fl)) :-
    l_int(holds(Fl, _), _).


% event_pred(+Ev)
%   True if Ev is an event predicate symbol.
%
event_pred(Ev) :-
    % Simple event predicates, externally generated events.
    event(Ev).
event_pred(Ev) :-
    % Simple event predicates, internally generated actions.
    action(Ev).
event_pred(Ev) :-
    % Composite event predicates, defined in L_events.
    l_events(happens(Ev, _, _), _).


% temp_constraint(+Term)
%   True if Term is an atomic temporal constraint formula.
%
temp_constraint(<(_,_)).
temp_constraint(=<(_,_)).


% reactive_conjunct(+Conj)
%   True if Conj is a valid conjunct in the antecedent or consequent of a
%   reactive rule.
%
reactive_conjunct(holds(F, _)) :-
    fluent_pred(F).
reactive_conjunct(X) :-
    X \= holds(_, _),
    X \= happens(_, _, _),
    X \= tc(_),
    l_timeless(X, _).
reactive_conjunct(happens(E, _, _)) :-
    event_pred(E).
reactive_conjunct(tc(T)) :-
    temp_constraint(T).


% l_timeless_body(P)
%
l_timeless_body(P) :-
    \+ holds(_, _),
    \+ happens(_, _, _).


% l_int_body(+P)
%
l_int_body(holds(P, _)) :-
    fluent_pred(P).
l_int_body(P) :-
    l_timeless(P, _).


% l_events_body(+P)
%
l_events_body(holds(P, _)) :-
    fluent_pred(P).
l_events_body(P) :-
    l_timeless(P, _).
l_events_body(happens(P, _, _)) :-
    event_pred(P).
l_events_body(tc(P)) :-
    temp_constraint(P).


% d_head(+H)
%
d_head(H) :-
    fluent(H).

% d_event(+H)
%
d_event(H) :-
    event(H).
d_event(H) :-
    action(H).


% d_body(+B)
%
d_body(happens(B, _, _)) :-
    event(B).
d_body(happens(B, _, _)) :-
    action(B).
d_body(holds(not(B), _)) :-
    fluent(B).
d_body(holds(B, _)) :-
    fluent(B).
d_body(B) :-
    l_timeless(B, _).
