-- Afstemnings-typer: 'dato' (dato-muligheder) eller 'tekst' (svarmuligheder).
alter table public.polls
  add column if not exists type text not null default 'dato'
    check (type in ('dato','tekst')),
  add column if not exists allow_multiple boolean not null default true;

-- Tekst-svar har ingen dato → option_tid skal kunne være NULL.
alter table public.poll_options alter column option_tid drop not null;
