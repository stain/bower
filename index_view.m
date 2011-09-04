%-----------------------------------------------------------------------------%

:- module index_view.
:- interface.

:- import_module char.
:- import_module io.
:- import_module list.

:- import_module data.
:- import_module screen.

%-----------------------------------------------------------------------------%

:- type index_info.

:- pred setup_index_view(list(thread)::in, index_info::out, io::di, io::uo)
    is det.

:- type action
    --->    continue
    ;       open_pager(thread_id)
    ;       enter_limit
    ;       start_compose
    ;       start_recall
    ;       quit.

:- pred index_view_input(screen::in, char::in, message_update::out,
    action::out, index_info::in, index_info::out) is det.

:- pred draw_index_view(screen::in, index_info::in, io::di, io::uo) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module bool.
:- import_module cord.
:- import_module int.
:- import_module require.
:- import_module string.
:- import_module time.

:- import_module curs.
:- import_module curs.panel.
:- import_module scrollable.
:- import_module time_util.

%-----------------------------------------------------------------------------%

:- type index_info
    --->    index_info(
                i_scrollable    :: scrollable(index_line)
            ).

:- type index_line
    --->    index_line(
                i_id        :: thread_id,
                i_new       :: new,
                i_unread    :: unread,
                i_replied   :: replied,
                i_flagged   :: flagged,
                i_date      :: string,
                i_authors   :: string,
                i_subject   :: string,
                i_total     :: int
            ).

:- type new
    --->    new
    ;       old.

:- type unread
    --->    unread
    ;       read.

:- type replied
    --->    replied
    ;       not_replied.

:- type flagged
    --->    flagged
    ;       unflagged.

:- type binding
    --->    scroll_down
    ;       scroll_up
    ;       skip_to_unread
    ;       enter
    ;       enter_limit
    ;       start_compose
    ;       start_recall
    ;       quit.

:- instance scrollable.line(index_line) where [
    pred(draw_line/5) is draw_index_line
].

%-----------------------------------------------------------------------------%

setup_index_view(Threads, Info, !IO) :-
    time(Time, !IO),
    Nowish = localtime(Time),
    list.foldl(add_thread(Nowish), Threads, cord.init, LinesCord),
    Lines = list(LinesCord),
    Cursor = 0,
    Scrollable = scrollable.init_with_cursor(Lines, Cursor),
    Info = index_info(Scrollable).

:- pred add_thread(tm::in, thread::in,
    cord(index_line)::in, cord(index_line)::out) is det.

add_thread(Nowish, Thread, !Lines) :-
    Thread = thread(Id, Timestamp, Authors, Subject, Tags, _Matched, Total),
    timestamp_to_tm(Timestamp, TM),
    Shorter = yes,
    make_reldate(Nowish, TM, Shorter, Date),
    Line0 = index_line(Id, old, read, not_replied, unflagged, Date, Authors,
        Subject, Total),
    list.foldl(apply_tag, Tags, Line0, Line),
    snoc(Line, !Lines).

:- pred apply_tag(string::in, index_line::in, index_line::out) is det.

apply_tag(Tag, !Line) :-
    ( Tag = "new" ->
        !Line ^ i_new := new
    ; Tag = "unread" ->
        !Line ^ i_unread := unread
    ; Tag = "replied" ->
        !Line ^ i_replied := replied
    ; Tag = "flagged" ->
        !Line ^ i_flagged := flagged
    ;
        true
    ).

%-----------------------------------------------------------------------------%

index_view_input(Screen, Char, MessageUpdate, Action, !IndexInfo) :-
    ( key_binding(Char, Binding) ->
        (
            Binding = scroll_down,
            move_cursor(Screen, 1, MessageUpdate, !IndexInfo),
            Action = continue
        ;
            Binding = scroll_up,
            move_cursor(Screen, -1, MessageUpdate, !IndexInfo),
            Action = continue
        ;
            Binding = skip_to_unread,
            skip_to_unread(Screen, MessageUpdate, !IndexInfo),
            Action = continue
        ;
            Binding = enter,
            enter(!.IndexInfo, Action),
            MessageUpdate = clear_message
        ;
            Binding = enter_limit,
            MessageUpdate = no_change,
            Action = enter_limit
        ;
            Binding = start_compose,
            MessageUpdate = no_change,
            Action = start_compose
        ;
            Binding = start_recall,
            MessageUpdate = no_change,
            Action = start_recall
        ;
            Binding = quit,
            MessageUpdate = no_change,
            Action = quit
        )
    ;
        MessageUpdate = no_change,
        Action = continue
    ).

:- pred key_binding(char::in, binding::out) is semidet.

key_binding('j', scroll_down).
key_binding('k', scroll_up).
key_binding('\t', skip_to_unread).
key_binding('\r', enter).
key_binding('l', enter_limit).
key_binding('m', start_compose).
key_binding('R', start_recall).
key_binding('q', quit).

:- pred move_cursor(screen::in, int::in, message_update::out,
    index_info::in, index_info::out) is det.

move_cursor(Screen, Delta, MessageUpdate, !Info) :-
    !.Info = index_info(Scrollable0),
    NumRows = list.length(Screen ^ main_panels),
    move_cursor(NumRows, Delta, HitLimit, Scrollable0, Scrollable),
    !:Info = index_info(Scrollable),
    (
        HitLimit = no,
        MessageUpdate = clear_message
    ;
        HitLimit = yes,
        ( Delta > 0 ->
            MessageUpdate = set_warning("You are on the last message.")
        ;
            MessageUpdate = set_warning("You are on the first message.")
        )
    ).

:- pred skip_to_unread(screen::in, message_update::out,
    index_info::in, index_info::out) is det.

skip_to_unread(Screen, MessageUpdate, !Info) :-
    !.Info = index_info(Scrollable0),
    NumRows = list.length(Screen ^ main_panels),
    ( get_cursor(Scrollable0, Cursor0) ->
        (
            search_forward(is_unread_line, Scrollable0, Cursor0 + 1, Cursor, _)
        ->
            set_cursor_centred(Cursor, NumRows, Scrollable0, Scrollable),
            MessageUpdate = clear_message
        ;
            search_forward(is_unread_line, Scrollable0, 0, Cursor, _),
            Cursor < Cursor0
        ->
            set_cursor_centred(Cursor, NumRows, Scrollable0, Scrollable),
            MessageUpdate = set_info("Search wrapped to top.")
        ;
            Scrollable = Scrollable0,
            MessageUpdate = set_warning("No unread messages.")
        )
    ;
        unexpected($module, $pred, "no cursor")
    ),
    !:Info = index_info(Scrollable).

:- pred is_unread_line(index_line::in) is semidet.

is_unread_line(Line) :-
    Line ^ i_unread = unread.

:- pred enter(index_info::in, action::out) is det.

enter(Info, Action) :-
    Info = index_info(Scrollable),
    ( get_cursor_line(Scrollable, CursorLine) ->
        ThreadId = CursorLine ^ i_id,
        Action = open_pager(ThreadId)
    ;
        Action = continue
    ).

%-----------------------------------------------------------------------------%

draw_index_view(Screen, Info, !IO) :-
    MainPanels = Screen ^ main_panels,
    Info = index_info(Scrollable),
    scrollable.draw(MainPanels, Scrollable, !IO).

:- pred draw_index_line(panel::in, index_line::in, bool::in,
    io::di, io::uo) is det.

draw_index_line(Panel, Line, IsCursor, !IO) :-
    Line = index_line(_Id, _New, Unread, Replied, Flagged, Date, Authors,
        Subject, Total),
    (
        IsCursor = yes,
        panel.attr_set(Panel, fg_bg(yellow, red) + bold, !IO)
    ;
        IsCursor = no,
        panel.attr_set(Panel, fg(blue) + bold, !IO)
    ),
    my_addstr_fixed(Panel, 11, Date, ' ', !IO),
    cond_attr_set(Panel, normal, IsCursor, !IO),
    (
        Unread = unread,
        Base = bold,
        my_addstr(Panel, "n", !IO)
    ;
        Unread = read,
        Base = normal,
        my_addstr(Panel, " ", !IO)
    ),
    (
        Replied = replied,
        my_addstr(Panel, "r", !IO)
    ;
        Replied = not_replied,
        my_addstr(Panel, " ", !IO)
    ),
    (
        Flagged = flagged,
        cond_attr_set(Panel, fg(red) + bold, IsCursor, !IO),
        my_addstr(Panel, "! ", !IO)
    ;
        Flagged = unflagged,
        my_addstr(Panel, "  ", !IO)
    ),
    cond_attr_set(Panel, Base, IsCursor, !IO),
    my_addstr_fixed(Panel, 25, Authors, ' ', !IO),
    cond_attr_set(Panel, fg(green) + Base, IsCursor, !IO),
    my_addstr(Panel, format(" %-3d ", [i(Total)]), !IO),
    cond_attr_set(Panel, normal, IsCursor, !IO),
    my_addstr(Panel, Subject, !IO).

:- pred cond_attr_set(panel::in, attr::in, bool::in, io::di, io::uo) is det.

cond_attr_set(Panel, Attr, IsCursor, !IO) :-
    (
        IsCursor = no,
        panel.attr_set(Panel, Attr, !IO)
    ;
        IsCursor = yes
    ).

:- func fg(colour) = attr.

fg(C) = curs.fg_bg(C, black).

%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sts=4 sw=4 et
