do setup.doh
*# st_version
nwrem version
*# st_toy
clear
input sender receiver t
1 2 1
1 3 2
2 1 3
1 2 4
3 2 5
2 3 6
1 3 7
3 1 8
2 1 9
1 3 10
end
nwset sender receiver, directed eventtime(t) name(chat)
nwsummarize chat
nwrem chat, nodsnd nidrec
