%%
:- dynamic action/1.
:- dynamic cacts/1.
:- dynamic current_goal/1.
:- dynamic current_time/1.
:- dynamic d_pre/1.
:- dynamic depth/1.
:- dynamic event/1.
:- dynamic expanded_consequent/2.
:- dynamic failed/3.
:- dynamic fluent/1.
:- dynamic happens/3.
:- dynamic initiated/3.
:- dynamic l_events/2. 
:- dynamic l_int/2.
:- dynamic l_timeless/2.
:- dynamic observe/2.
:- dynamic option/1.
:- dynamic reactive_rule/2.
:- dynamic state/1.
:- dynamic steps/1.
:- dynamic succ_t/2.
:- dynamic susp/1.
:- dynamic terminated/3.
:- dynamic tried/3.
:- dynamic used/1.
:- dynamic this_initiated/1.

event(X) :-
    action(X).
