* the e-mail data of the manual: the first five days of the manufacturing e-mails (631 events) as the event network mail;
* the 144 employees who do not write or receive in the window are added as isolates (they are still possible actors).
nwwebuse manufacturing, nwclear
levelsof sender, local(a) clean
levelsof receiver, local(b) clean
local all : list a | b
keep if t < 5
levelsof sender, local(a) clean
levelsof receiver, local(b) clean
local present : list a | b
local miss : list all - present
nwset sender receiver, directed eventtime(t) name(mail)
local miss : subinstr local miss " " ",", all
nwaddnodes mail, nodenames(`miss')
