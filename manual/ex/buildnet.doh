* program nwbuild name: declares the events in memory (variables sender, receiver, t) as the event network name, with the
* actors in the global macro allact that do not occur in the events added as isolates
capture program drop nwbuild
program nwbuild
	args name
	quietly levelsof sender, local(a) clean
	quietly levelsof receiver, local(b) clean
	local present : list a | b
	local miss : list global(allact) - present
	nwset sender receiver, directed eventtime(t) name(`name')
	if "`miss'" != "" {
		local miss : subinstr local miss " " ",", all
		nwaddnodes `name', nodenames(`miss')
	}
end
