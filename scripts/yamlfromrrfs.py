# ---------------------------------------------------------------------------
# yamlfromrrfs.py — merged YAML utilities for RRFSv2 / WoFS JEDI workflows
#   Combines the functions from hifiyaml4rrfs.py and yamltools4rrfs.py that
#   are needed by yaml_finalize.py (unused helpers have been omitted).
# ---------------------------------------------------------------------------

import os
import re
import sys

# ===========================================================================
# Low-level YAML helpers  (originally hifiyaml4rrfs.py)
# ===========================================================================

def load(fpath, replacements=None):
    """Load a YAML file into a list of lines, optionally substituting @VAR@ tokens."""
    pattern = re.compile(r"@(\w+)@")
    data = []
    with open(fpath, 'r') as infile:
        for line in infile:
            line = line.rstrip()
            if replacements:
                line = pattern.sub(lambda m: replacements.get(m.group(1), m.group(0)), line)
            data.append(line)
    return data


def text_to_yblock(text):
    """Convert a multi-line string to a hifiyaml block (list of lines)."""
    return text.splitlines()


def strip_indentations(ystr):
    """Return (nspace, spaces, stripped_line) for a YAML line."""
    org_len = len(ystr)
    ystr_stripped = ystr.lstrip(' ')
    nspace = org_len - len(ystr_stripped)
    return nspace, ' ' * nspace, ystr_stripped.strip()


def strip_leading_empty_lines(block):
    """Remove leading empty lines from a YAML block in place."""
    while block and block[0] == "":
        block.pop(0)


def dedent(block):
    """Remove common leading indentation from a YAML block in place."""
    pos = -1
    for i in range(len(block)):
        if not block[i].strip().startswith("#"):
            pos = i
            break
    if pos == -1:
        return

    nspaceBlock = strip_indentations(block[pos])[0]
    if nspaceBlock > 0:
        for i in range(len(block)):
            nspace = strip_indentations(block[i])[0]
            if nspace < nspaceBlock:
                block[i] = block[i][nspace:]
            else:
                block[i] = block[i][nspaceBlock:]


def next_pos(data, pos, querystr=""):
    """Return the index of the next peer or ancestor YAML block."""
    if pos == -1:
        return len(data)
    query_list = querystr.strip("/").split("/")

    line1 = data[pos]
    nspace, spaces, line1 = strip_indentations(line1)
    if len(query_list) >= 2 and query_list[-2].isdigit() and not query_list[-1].isdigit():
        line1 = line1[2:]
        nspace += 2
        spaces += "  "

    end = len(data)
    result = None
    for i in range(pos + 1, end):
        nspace2, spaces2, line2 = strip_indentations(data[i])
        if not line2 or line2.startswith("#"):
            pass
        elif nspace2 == nspace:
            if line1.startswith("- "):
                result = i
                break
            else:
                if not line2.startswith("- "):
                    result = i
                    break
        elif nspace2 < nspace:
            result = i
            break

    if result is None:
        result = end
    else:
        for i in range(result - 1, pos, -1):
            nspace2 = strip_indentations(data[i])[0]
            if data[i].strip().startswith('#') and nspace2 <= nspace:
                result = i
            else:
                break

    return result


def get_start_pos(data, querystr="", ignore_error=False, linestr=""):
    """Return (position, errmsg) for the YAML block identified by querystr or linestr."""
    errmsg = None
    if querystr:
        query_list = querystr.strip("/").split("/")
    else:
        if not linestr:
            return -1, None
        else:
            query_list = ["place:holder:query:list:longmont:colorado:USA"]

    cur = 0
    end = len(data)

    for s in query_list:
        found = False
        for i in range(cur, end):
            line = data[i].strip()
            if s.isdigit():
                line = re.sub(r'(["\']).*?\1', r'\1\1', line)
                if "[" in line:
                    errmsg = "!! Directly modifying [....] needs further development !!"
                    if not ignore_error:
                        sys.stderr.write(f"{errmsg}\n")
                        sys.exit(1)
                elif "- " in line:
                    nextpos = i
                    knt = int(s)
                    for j in range(0, knt):
                        nextpos = next_pos(data, nextpos, querystr)
                    cur = nextpos
                    found = True
                    break
            else:
                if (linestr and linestr in data[i]) or f"{s}:" in line:
                    cur = i
                    found = True
                    break
        if not found:
            errmsg = f"key error: '{s}' not found\n"
            if not ignore_error:
                sys.stderr.write(f"{errmsg}\n")
                sys.exit(1)

    return cur, errmsg


def get(data, querystr, do_dedent=True):
    """Return a (optionally dedented) copy of the YAML block identified by querystr."""
    if querystr == "":
        pos1 = 0
        pos2 = len(data)
    else:
        pos1, _ = get_start_pos(data, querystr)
        pos2 = next_pos(data, pos1, querystr)

    for i in range(pos1 - 1, -1, -1):
        if data[i].strip().startswith('#'):
            pos1 = i
        else:
            break

    block = data[pos1:pos2]
    if do_dedent:
        dedent(block)
    return block


def dump(data, querystr="", fpath=None):
    """Print or write the YAML block identified by querystr."""
    if fpath is not None:
        outfile = open(fpath, 'w')
    block = get(data, querystr)
    for line in block:
        if fpath is None:
            print(line)
        else:
            outfile.write(line + '\n')
    if fpath is not None:
        outfile.close()


def modify(data, querystr, newblock, oneline_change=False):
    """Replace the YAML block identified by querystr with newblock."""
    if isinstance(newblock, str):
        newblock = text_to_yblock(newblock)

    if querystr == "":
        return

    pos1, _ = get_start_pos(data, querystr)
    pos2 = next_pos(data, pos1, querystr)

    nspace, spaces, _ = strip_indentations(data[pos1])

    for i in range(pos1 - 1, -1, -1):
        if data[i].strip().startswith('#'):
            pos1 = i
        else:
            break

    strip_leading_empty_lines(newblock)
    dedent(newblock)
    if nspace > 0:
        for i, line in enumerate(newblock):
            newblock[i] = spaces + line

    if oneline_change:
        data[pos1] = newblock[0]
    else:
        data[pos1:pos2] = newblock


# ===========================================================================
# Higher-level observation helpers  (originally yamltools4rrfs.py)
# ===========================================================================

def load_convinfo(confilename='convinfo'):
    """Load a convinfo file and return a dictionary keyed by obs type."""
    dcConvInfo = {}
    if os.path.exists(confilename):
        with open(confilename, 'r') as sfile:
            for line in sfile:
                if not line.strip().startswith("!"):
                    fields = line.split()
                    if len(fields) == 9:
                        atype = fields[0]
                        if fields[1] != '0':
                            atype += fields[1].zfill(3)
                        if fields[2] != '0':
                            atype += "_" + fields[2].zfill(3)
                        dcConvInfo[atype] = {
                            'iuse':    fields[3],
                            'twindow': fields[4],
                            'gross':   fields[5],
                            'ermax':   fields[6],
                            'ermin':   fields[7],
                            'msgtype': fields[8],
                        }
                    else:
                        sys.stderr.write(f"read_convinfo Warning: expected 9 fields\n{line}\n")
    return dcConvInfo


def get_all_filters(data, pos1, pos2):
    """Return a list of filter dictionaries within the line range [pos1, pos2)."""
    filters = []
    cur = pos1

    while cur < pos2:
        for i in range(cur, pos2):
            if "- filter:" in data[i] and not data[i].strip().startswith("#"):
                cur = i
                break

        category = data[cur].split(":")[1].strip()
        next_one = next_pos(data, cur)

        nspace = strip_indentations(data[cur])[0]
        for i in range(cur - 1, -1, -1):
            nspace2, _, line = strip_indentations(data[i])
            if nspace2 == nspace and line.startswith('#'):
                cur = i
            else:
                break

        dcFilter = {
            "category": category,
            "pos1": cur,
            "pos2": next_one,
            "block": data[cur:next_one],
        }
        filters.append(dcFilter)
        cur = next_one

    return filters


def get_all_obs(data, shallow=False):
    """Return a dictionary of all observers found in a JEDI YAML data list."""
    dcObs = {}
    cur = 0
    end = len(data)

    while cur < end:
        for i in range(cur, end):
            if "- obs space:" in data[i]:
                cur = i
                break

        if cur + 1 >= end:
            break
        name = data[cur + 1].split(":")[1].strip()
        next_one = next_pos(data, cur)

        is_sat_radiance = any("name: CRTM" in data[i] for i in range(cur, next_one))

        if name.endswith("_night"):
            sname = name
        else:
            tmp = name.split("_", 1)
            if len(tmp) > 1 and not is_sat_radiance:
                sname = tmp[1].strip()
            else:
                sname = name

        nspace = strip_indentations(data[cur])[0]
        for i in range(cur - 1, -1, -1):
            nspace2, _, line = strip_indentations(data[i])
            if nspace2 <= nspace and line.startswith('#'):
                cur = i
            else:
                break

        obs = {
            "name": name,
            "sname": sname,
            "is_sat_radiance": is_sat_radiance,
            "pos1": cur,
            "pos2": next_one,
            "pre filters": {},
            "filters": {},
            "prior filters": {},
            "post filters": {},
            "block": [],
        }

        if not shallow:
            obs["block"] = data[cur:next_one]

            def assemble_filters(key):
                for i in range(cur, next_one):
                    if f"obs {key}:" in data[i]:
                        pos1 = i
                        pos2 = next_pos(data, pos1)
                        obs[key] = get_all_filters(data, pos1, pos2)
                        break

            assemble_filters("filters")
            assemble_filters("pre filters")
            assemble_filters("prior filters")
            assemble_filters("post filters")

        dcObs[name] = obs
        cur = next_one

    return dcObs


def getkf_observer_tweak(data, getkf_type):
    """
    Tweak observers for getkf solver or post mode:
      - solver: replace RoundRobin distribution with Halo
      - both:   transfer obsdataout obsfile to obsdatain
      - post:   remove 'reduce obs space' actions and Temporal Thinning filters
    Pass the full list (not a slice) so in-place edits are reflected.
    """
    if getkf_type == "solver":
        for i in range(len(data)):
            if "RoundRobin" in data[i]:
                data[i] = data[i].replace("RoundRobin", "Halo")

    pos, _ = get_start_pos(data, "obsdataout/engine/obsfile")
    diagfile = data[pos].split(":")[1].strip()
    pos, _ = get_start_pos(data, "obsdatain/engine/obsfile")
    spaces = strip_indentations(data[pos])[1]
    data[pos] = f"{spaces}obsfile: jdiag/{diagfile}"

    if getkf_type == "post":
        i = 0
        while i < len(data) - 1:
            if (data[i].strip().startswith("action:") and
                    data[i + 1].strip().startswith("name: reduce obs space")):
                del data[i:i + 2]
            else:
                i += 1

        pos, errmsg = get_start_pos(data, linestr="- filter: Temporal Thinning", ignore_error=True)
        if errmsg is None and not data[pos].strip().startswith("#"):
            next_one = next_pos(data, pos)
            del data[pos:next_one]
