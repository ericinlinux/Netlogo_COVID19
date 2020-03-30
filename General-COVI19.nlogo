;;;;;;

extensions [ csv ]

globals [
  contact-daily
  contagion-prob-daily
  #-icus-available

  #-icus-public
  #-icus-private

  deaths-virus
  deaths-infra
]

patches-own [
]

turtles-own[
  old?        ;; elder?
  favela?     ;; live in a favela?
  infected?   ;; not infected or infected?
  immune?
  hospitalized?
  never-infected?
  icu?
  dead?
  severity    ;; level of severity 0 (Asymptomatic) 1 (Mild) 2 (Severe) 3 (Critical)

  days-infected
  #-transmitted

  num-contacts
  prob-spread

  ;;; interventions
  isolated?  ;; agent in quarentine
  id-number

  icu-private? ;; if the agent goes to the private ICU

]

to setup
  ca
  setup-globals
  setup-map
  populate
  setup-ties
  infect-first
  reset-ticks
end

;;;;
to setup-globals
  load-statistics
  ; distribution of the ICUs
  set #-icus-available #-icus
  set #-icus-public #-icus * perc-icus-public / 100
  set #-icus-private #-icus * (100 - perc-icus-public) / 100

  set deaths-virus 0
  set deaths-infra 0
end

;;;;
to setup-map
  resize-world -310 310 -280 280
  set-patch-size 1
  ask patches with [pxcor < 0 ] [set pcolor yellow]
  ask patches with [pxcor >= 0 ] [set pcolor 88]
end

;;;;
to populate
  ; create turtles
  create-turtles num-population [
    set shape "person"
    set size 9
    set infected? false
    set immune? false
    set hospitalized? false
    set icu? false
    set dead? false
    set never-infected? true
    set #-transmitted 0
    set isolated? false
    set id-number random 10

    ifelse random-float 100 < perc-idosos [ ; if old or young
      ; create old
      set old? true
      set color orange
    ] [
      ; create young
      set old? false
      set color green
    ]
    ; if live in a favela
    ifelse random-float 100 < perc-favelas [
      set favela? true
      set shape "person"
      set size 9
      ;; which health system? favela-perc-private & non-perc-private
      ifelse favela-perc-private > random 100 [ set icu-private? true ] [ set icu-private? false ] ;;
    ] [
      set favela? false
      ifelse nonfavela-perc-private > random 100 [ set icu-private? true ] [ set icu-private? false ]
    ]
  ]

  ;layout-circle turtles  120
  ;layout-circle turtles with [ favela? ] 100
  ask turtles with [favela?] [
    ;let random-x random min-pxcor 0
    move-to one-of patches with [pcolor = 88 and not any? turtles-here]
    ;set heading 90
    ;fd 160
  ]
  ask turtles with [not favela?] [
    ;set heading 270
    ;fd 160
    move-to one-of patches with [pcolor = yellow and not any? turtles-here]
  ]
end

;;;;
to setup-ties
  ask turtles with [favela?] [
    create-links-to n-of #-intra-connections other turtles with [favela?] [
      hide-link
    ]
    create-links-to n-of #-inter-connections other turtles with [not favela?] [
      hide-link
    ]
  ]

  ;; people NOT from the favelas
  ask turtles with [not favela?] [
    create-links-to n-of #-intra-connections other turtles with [not favela?] [
      hide-link
    ]
    create-links-to n-of #-inter-connections other turtles with [favela?] [
      hide-link
    ]
  ]
end

to infect-first
   infect n-of initial-infected turtles
end


;;;; INFECT PROCEDURES
to infect [ person ]
  ask person [
    set infected? true
    set never-infected? false
    set immune? false
    set days-infected 0

    ;; define severity
    let chance random 100
    ifelse old? [ ;old
      ifelse chance < 20 [
        set severity 0
      ] [
        ifelse chance < 40 [
          set severity 1
        ][
          ifelse chance < 60 [
            set severity 2
          ][
            set severity 3
          ]
        ]
      ]
    ] [ ; young
      ifelse chance < 60 [
        set severity 0
      ][
        ifelse chance < 80 [
          set severity 1
        ][
          ifelse chance < 98 [
            set severity 2
          ][
            set severity 3
          ]
        ]
      ]
    ]

    set num-contacts item days-infected (item severity contact-daily) ; get the number of contacts based on the severity of the person and the days of infection
    set prob-spread item days-infected (item severity contagion-prob-daily)
    set shape "person doctor"
    set size 9
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to go
  ;if ticks = 120 [stop]
  if count turtles with [infected? or hospitalized? or icu?] = 0 [stop]
  if debug? [type count turtles with [infected?] type " " type count turtles with [hospitalized?] type " " type count turtles with [icu?] type "\n"]
  disease-development
  interact-with-others

  tick
end

; interactions between infected people
to interact-with-others
  ; only infected turtles matter for the spread of the virus
  ask turtles with [infected? and not dead?] [
    let numlinks count my-links
    let contagion-probability prob-spread

    let intra 2 * num-contacts / 3 ;; contacts with people from the same group
    let inter num-contacts / 3;; contacts with people from the other group

    if debug? [type self type " has " type numlinks type " links and " type num-contacts type " contacts\n"]

    let sTurtle self

    ifelse numlinks >= intra [  ; if the number of contacts is bigger than the number of friends/family
      ask n-of numlinks link-neighbors [
        ;
        if not infected? and not immune? and not dead? [
          if random-float 100 <= contagion-probability [
            if debug? [type sTurtle type " infected " type self type "\n"]
            infect self
            ask sTurtle [set #-transmitted #-transmitted + 1]  ; increment the number of transmitted
          ]
        ]
      ]
    ][ ; less close contacts than daily contacts
      ask link-neighbors [
        if not infected? and not immune? and not dead? [
          if debug? [type "Neighbor not infected: " type self type "\n"]
          if random-float 100 <= contagion-probability [
            if debug? [type sTurtle type " infected " type self type "\n"]
            infect self
            ask sTurtle [set #-transmitted #-transmitted + 1]
          ]
        ]
      ]
      ;;;; some contacts will be repeated
      let contacts-left intra - count link-neighbors
      let n-iterations 0
      while [contacts-left > 0] [
        ifelse contacts-left >= (count link-neighbors) [
          set n-iterations count link-neighbors
        ][
          set n-iterations contacts-left
        ]

        ask n-of n-iterations link-neighbors [
          if debug? [type "Turtle " type sTurtle type " -> Neighbors: " type self type "\n"]
          if debug? [type "Contagion probability: " type contagion-probability type "\n"]
          ;
          if not infected? and not immune? and not dead? [
            if debug? [type "Neighbor not infected: " type self type "\n"]
            if random-float 100 <= contagion-probability [
              if debug? [type sTurtle type " infected " type self type "\n"]
              infect self
              ask sTurtle [set #-transmitted #-transmitted + 1]
            ]
          ]
        ]
        set contacts-left contacts-left - count link-neighbors
      ]
      ; infect not close ties
      ;let num-others num-contacts - numlinks ; contacts to make besides the close ones done before
      ask n-of inter turtles with [ not (member? sTurtle link-neighbors) and not (isolated?) ][

        if debug? [type self type "\n"]

        if not infected? and not immune? and not dead? [
          if random-float 100 <= contagion-probability [
            if debug? [type sTurtle type " infected " type self type "\n"]
            infect self
            ask sTurtle [set #-transmitted #-transmitted + 1]
          ]
        ]
      ]

    ] ; end if
  ] ; end ask turtles
end


; Development of the infected people
to disease-development
  ask turtles with [infected? and not dead?] [
    ; increment day
    set days-infected days-infected + 1
    ; update information from the cases
    set num-contacts item days-infected (item severity contact-daily) ; get the number of contacts based on the severity of the person and the days of infection
    set prob-spread item days-infected (item severity contagion-prob-daily)

    if severity = 0 or severity = 1[
      if days-infected = 27 [
        set infected? false
        set immune? true
        set shape "face happy"
        set size 9
      ]
    ] ; end severity = 0 or 1

    if severity = 2 [
      if days-infected = 11 [ hospitilize self]
      if days-infected = 27 [
        set infected? false
        set hospitalized? false
        set immune? true
        set shape "face happy"
        set size 9
      ]
    ] ; end severity = 2

    if severity = 3 [
      if days-infected = 11 [ hospitilize self]
      if days-infected = 17 [ icu self]
      if days-infected = 27 [
        ; free icus
        set #-icus-available #-icus-available + 1
        ifelse icu-private? [ set #-icus-private #-icus-private + 1 ] [set #-icus-public #-icus-public + 1 ]
        ; chance of death
        ifelse random-float 100 < 80 [ ; 80% of chance to die
          ; die
          if debug? [type self type "DIED in the ICU!!!\n"]

          set hospitalized? false
          set icu? false
          set infected? false

          set dead? true
          ;set hidden? true
          set shape "x"
          ask my-links [die]
          set deaths-virus deaths-virus + 1 ; deaths because of the virus
        ][
          set hospitalized? false
          set icu? false
          set infected? false

          set shape "face happy"
          set size 9
          set immune? true
        ]

      ]
    ] ; end severity = 3

  ]
end


to hospitilize [ person ] ; this may be adjusted in the future for cases when the number of beds is not suficient
  set hospitalized? true

end


to icu [ person ]
  ask person [
    ; if icu is private
    ifelse icu-private? [   ;;; private
      ifelse #-icus-private > 0 [
        set icu? true
        set hospitalized? false
        set #-icus-available #-icus-available - 1
        set #-icus-private #-icus-private - 1
      ][
        ; die
        if debug? [type self type "DIED for the lack of ICUs!!!\n"]
        set hospitalized? false
        set icu? false
        set infected? false

        set dead? true
        ;set hidden? true
        set shape "x"
        ask my-links [die]
        set deaths-infra deaths-infra + 1 ; deaths because of lack of infrastructure
      ]
    ][
      ; if icu is public
      ifelse #-icus-public > 0 [
        set icu? true
        set hospitalized? false
        set #-icus-available #-icus-available - 1
        set #-icus-public #-icus-public - 1
      ][
        ; die
        if debug? [type self type "DIED for the lack of ICUs!!!\n"]
        set hospitalized? false
        set icu? false
        set infected? false

        set dead? true
        ;set hidden? true
        set shape "x"
        ask my-links [die]
        set deaths-infra deaths-infra + 1 ; deaths because of lack of infrastructure
      ]
    ]
  ]
end


;;;; STATISTICS OF NUMBER OF CONTACTS AND CONTAGION PROBABILITY
to load-statistics
  let file1 "./data/contacts_daily.csv"
  let file2 "./data/contagion_chance.csv"
  set contact-daily read-csv-to-list file1
  set contagion-prob-daily read-csv-to-list file2
end


;;;;;;;;
;; ISOLATION

to isolate-perc
  let perc-pop count turtles * perc-isolated / 100
  ask n-of perc-pop turtles with [ not hospitalized? and not icu? and not dead? ] [
    set isolated? true
    set color black
  ]
end

to isolate-elderly
  ask turtles with [ old? ] [
    set isolated? true
    set color black
  ]
end

to isolate-id
  ask turtles with [not hospitalized? and not icu? and not dead?][
    set isolated? true
    set color black
  ]

  ask turtles with [ ticks mod 10 = id-number ] [
    if not hospitalized? and not icu? and not dead? [
      set isolated? false
      ifelse old? [ set color orange ][ set color green ]
    ]
  ]
end

to free-people
  ask turtles with [isolated?][
    ifelse old? [
      set color orange
    ][
      set color green
    ]
  ]
end


;;;; SECONDARY PROCEDURES

to-report read-csv-to-list [ file ]
  file-open file
  let returnList []
  while [ not file-at-end? ] [
    let row (csv:from-row file-read-line ",")
    set returnList lput row returnList
  ]
  if debug? [  show returnList ]
  file-close
  report returnList
end
@#$#@#$#@
GRAPHICS-WINDOW
772
10
1401
580
-1
-1
1.0
1
10
1
1
1
0
0
0
1
-310
310
-280
280
0
0
1
ticks
30.0

SLIDER
11
57
196
90
num-population
num-population
100
10000
1800.0
100
1
people
HORIZONTAL

SWITCH
13
343
116
376
debug?
debug?
1
1
-1000

SLIDER
8
142
195
175
perc-idosos
perc-idosos
0
100
30.0
1
1
%
HORIZONTAL

SLIDER
8
100
195
133
perc-favelas
perc-favelas
0
100
64.0
1
1
%
HORIZONTAL

BUTTON
9
12
75
45
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
422
437
580
482
People from the Favelas
count turtles with [favela? = true]
17
1
11

MONITOR
419
485
581
530
People not from the Favelas
count turtles with [favela? = false]
17
1
11

MONITOR
420
534
581
579
Average Degree
count links / count turtles
2
1
11

MONITOR
268
477
402
522
Infected (%)
count turtles with [infected?] * 100 / count turtles
2
1
11

BUTTON
88
13
160
46
NIL
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

SLIDER
8
183
196
216
#-icus
#-icus
0
100
20.0
1
1
ICUs
HORIZONTAL

SLIDER
431
588
623
621
#-beds
#-beds
0
100
100.0
1
1
beds
HORIZONTAL

MONITOR
595
339
726
384
Hospitalized
count turtles with [hospitalized?]
17
1
11

MONITOR
594
388
725
433
People on ICUs
count turtles with [icu?]
17
1
11

BUTTON
170
14
233
47
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

PLOT
466
171
761
332
Infected people
Days
# of people
0.0
90.0
0.0
100.0
true
true
"" ""
PENS
"Infected" 1.0 0 -13345367 true "" "plot count turtles with [infected?]"
"Hospitalized + ICUs" 1.0 0 -14439633 true "" "plot count turtles with [hospitalized? or icu?]"
"Dead" 1.0 0 -2674135 true "" "plot count turtles with [dead?]"

MONITOR
602
460
746
505
ICUs Available (Total)
#-icus-available
17
1
11

PLOT
466
10
762
160
People's statuses
Days
# of people
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"Hospitalized" 1.0 0 -16777216 true "" "plot count turtles with [hospitalized? and not dead?]"
"ICUs" 1.0 0 -14439633 true "" "plot count turtles with [icu? and not dead?]"
"ICUs (max)" 1.0 0 -5298144 true "" "plot #-icus"

MONITOR
1030
590
1176
635
Total Deaths
count turtles with [dead?]
17
1
11

MONITOR
270
372
414
417
Deaths (Lack of ICUs)
deaths-infra
17
1
11

MONITOR
270
425
415
470
Deaths (Virus)
deaths-virus
17
1
11

MONITOR
452
338
589
383
Healed (%)
count turtles with [immune?] * 100 / count turtles
2
1
11

SLIDER
13
386
187
419
initial-infected
initial-infected
1
5
2.0
1
1
person(s)
HORIZONTAL

MONITOR
814
591
1012
636
Average transmission
sum [#-transmitted] of turtles with [not never-infected?]/ count turtles with [not never-infected?]
2
1
11

MONITOR
453
387
588
432
Never infected (%)
count turtles with [never-infected?] * 100 / count turtles
2
1
11

MONITOR
1187
589
1320
634
Deaths (%)
count turtles with [dead?] * 100 / count turtles
2
1
11

TEXTBOX
1207
551
1247
569
Favela
11
0.0
0

SLIDER
12
426
214
459
#-inter-connections
#-inter-connections
1
20
2.0
1
1
person(s)
HORIZONTAL

SLIDER
10
463
216
496
#-intra-connections
#-intra-connections
1
20
4.0
1
1
person(s)
HORIZONTAL

MONITOR
267
528
394
573
# of people infected
count turtles with [infected?]
17
1
11

SLIDER
7
222
197
255
perc-icus-public
perc-icus-public
0
100
30.0
1
1
%
HORIZONTAL

MONITOR
601
512
744
557
ICUs Available (Public)
#-icus-public
17
1
11

MONITOR
635
573
781
618
ICUs Available (Private)
#-icus-private
17
1
11

SLIDER
11
505
193
538
favela-perc-private
favela-perc-private
0
100
10.0
1
1
%
HORIZONTAL

SLIDER
10
548
195
581
nonfavela-perc-private
nonfavela-perc-private
0
100
80.0
1
1
%
HORIZONTAL

TEXTBOX
288
11
438
207
Isolations scenarios\n
14
13.0
0

SLIDER
7
259
194
292
risk-rate-favela
risk-rate-favela
100
200
120.0
1
1
%
HORIZONTAL

SLIDER
251
162
423
195
perc-isolated
perc-isolated
0
100
50.0
1
1
%
HORIZONTAL

BUTTON
250
40
348
73
Isolate %
isolate-perc
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
251
121
349
154
Quit quarentine
free-people
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
359
40
457
73
Isolate Elderly
isolate-elderly
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
251
80
348
113
Isolate by ID
isolate-id
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

@#$#@#$#@
## WHAT IS IT?

This is a general model for the transmission of COVID-19 in poor communities known in Brazil as favelas. The model is created by a team of specialists in infectology, virology, computer science, logistics, veterinary among other expertises and aims to simulate a generic scenario for the spread of the virus under normal conditions.

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

This model was developed by a team of researchers, health professionals, and members of the Brazilian Army. The main programmer and modeller is Eric Araújo (eric@ufla.br), to whom you could send requests for clarification or questions regarding the model.
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

lander
true
0
Polygon -7500403 true true 45 75 150 30 255 75 285 225 240 225 240 195 210 195 210 225 165 225 165 195 135 195 135 225 90 225 90 195 60 195 60 225 15 225 45 75

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

person doctor
false
0
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Polygon -13345367 true false 135 90 150 105 135 135 150 150 165 135 150 105 165 90
Polygon -7500403 true true 105 90 60 195 90 210 135 105
Polygon -7500403 true true 195 90 240 195 210 210 165 105
Circle -7500403 true true 110 5 80
Rectangle -7500403 true true 127 79 172 94
Polygon -1 true false 105 90 60 195 90 210 114 156 120 195 90 270 210 270 180 195 186 155 210 210 240 195 195 90 165 90 150 150 135 90
Line -16777216 false 150 148 150 270
Line -16777216 false 196 90 151 149
Line -16777216 false 104 90 149 149
Circle -1 true false 180 0 30
Line -16777216 false 180 15 120 15
Line -16777216 false 150 195 165 195
Line -16777216 false 150 240 165 240
Line -16777216 false 150 150 165 150

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.1.1
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
