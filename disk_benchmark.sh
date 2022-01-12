#!/bin/bash
#
# Aqua Ray disk benchmark
# www.aquaray.com
#

ioping_count=60
declare -a ioengine_array=("libaio")
declare -a jobs_array=(1 2 4 8 16 32 64)
declare -a iodepth_array=(1)
declare -a sync_array=(0 1)
declare -a direct_array=(1)
declare -a rw_array=('write' 'randwrite' 'read' 'randread') #RW_Array possible values : read, write, randread, randwrite, rw, readwrite, randrw
declare -a bs_array=('4k')
declare -a runtime_array=(60)
readonly use_color=1

declare -a disks=()
export_to_file=0
verbose=0

my_banner()
{
    width=$((25+${#1}))
    width_for_txt=$((width-6))
    width=$((width+1))

    divider="##############################################################################################"
    divider="$divider$divider"

    D="$1"                # input string
    BS=$width_for_txt     # buffer size
    L=$(((BS-${#D})/2))
    [ $L -lt 0 ] && L=0

    echo "${GREEN}"
    printf "%$width.${width}s\n" "$divider"
    printf "## %$((width-6))s ##\n" ""
    printf "%s %${L}s %s %${L}s %s\n" "##" "" "$1" "" "##"
    printf "## %$((width-6))s ##\n" ""
    printf "%$width.${width}s\n" "$divider"
    echo "${WHITE}"
}

info()
{
    echo "[${GREEN}**${WHITE}]" "${@}"
}
warn()
{
    echo "[${YELLOW}!!${WHITE}]" "${@}" >&2
}

die()
{
    if [ $# -ne 0 ]; then
	echo "[${RED}!!${WHITE}]" "$@" >&2
    else
	echo "[${RED}!!${WHITE}] Unknow Error" >&2
    fi

    exit 1
}

function usage
{
    if [ $# -ne 0 ]; then
        echo $(basename "$0")": Error: ${RED}" "$@" "${WHITE}"
        echo ""
    else
        echo ""
        echo "${GREEN}Help for $(basename $0)${WHITE}"
        echo ""
    fi

    echo "$(basename $0) [-h] [-v] [--ioping-count <count>] [--export <folder>] -d <disk1> [-d <disk2> ...]"
    echo "disk_benchmark.sh [options] <disk list> "
    echo "  -h                   Display this help"
    echo "  -v                   Show tools output"
    echo "  -d /dev/disk1        Test the disk '/dev/disk1'. This option can be used"
    echo "                       multiple times to test different disk in the same run."
    echo "  --ioping-count x     Change the ioping count"
    echo "  --export folder      Use this folder to write csv files"
    exit 1
}

if [ ${use_color} -eq 1 ]; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    VIOLET=$(tput setaf 5)
    CYAN=$(tput setaf 6)
    WHITE=$(tput setaf 7)
    GREY=$(tput setaf 8)
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    VIOLET=""
    CYAN=""
    WHITE=""
    GREY=""
fi


: "${BC:=$(which bc)}"
: "${IOPING:=$(which ioping)}"
: "${FIO:=$(which fio)}"
[ ! -x "${BC}" ] && die "Error: bc '${BC}' not found or not executable"
[ ! -x "${IOPING}" ] && die "Error: ioping '${IOPING}' not found or not executable"
[ ! -x "${FIO}" ] && die "Error: fio '${FIO}' not found or not executable"

TEMP=$(getopt -o hvd: --long disk:,export:,ioping-count: -n "$(basename $0)" -- "$@")
if [ $? -ne 0 ]; then
    usage
fi

eval set -- "$TEMP"

while true; do
    case "$1" in
	-h) usage;;
	-v) verbose=1;
	    shift;;
	-d) disks=(${disks[@]} "${2}");
	    shift 2;;
	--ioping-count) ioping_count=$2;
			shift 2;;
	--export)
	    export_to_file=1;
	    RESULT_FOLDER="${2}";
	    shift 2;;
	--) shift ; break;;
	*) die "Internal error!";;
    esac
done

if [ "${#disks}" -eq 0 ]; then
    usage "at lease one disk must be set (-d option)"
fi

if [[ -z "${ioping_count}" ]] || ! [[ "${ioping_count}" =~ ^[0-9]+$ ]]; then
    usage "--ioping-count must be a number ('${ioping_count}')"
fi

if [ ${export_to_file} -eq 1 ]; then
    if [[ ! -d "${RESULT_FOLDER}" ]]; then
	die "Folder '${RESULT_FOLDER}' does not exists"
    fi
fi


my_banner "WARNING !!";

read -p "The test will DESTROY data on disks. Do you want to continue ? (y/N) " CONTINUE_OR_NOT
if [ "${CONTINUE_OR_NOT}" != "y" ]; then
    die "Canceled by user."
fi

readonly test_count=$((${#disks[@]} * ${#ioengine_array[@]} * ${#jobs_array[@]} * ${#iodepth_array[@]} * ${#sync_array[@]} * ${#direct_array[@]} * ${#rw_array[@]} * ${#bs_array[@]} * ${#runtime_array[@]} + ${#disks[@]}))
test_number=1
disk_number=0

for disk_dev in "${disks[@]}"; do
    disk_number=$((disk_number + 1))
    declare -a disk_results=()

    DISK_MODEL=$(echo $(hdparm -I ${disk_dev} | grep -i model | cut -d : -f 2));

    DISK_SIZE=($(hdparm -I ${disk_dev} | sed -n "s|device size with M = 1000\*1000:.*(\([0-9]\+\) \([a-zA-Z]\+\))|\1 \2|gp"))
    if [ ${#DISK_SIZE[@]} -ne 2 ]; then
	warn "Cannot parse disk size"
    fi
    DISK_FIRMWARE=$(hdparm -I ${disk_dev} | sed -n "s|.*Firmware Revision:[[:space:]]*\(.\+\)|\1|gp")
    if [ -z "${DISK_FIRMWARE}" ]; then
	warn "Cannot parse disk firmware"
    fi

    DISK_MODEL_NO_SPACE=$(echo "${DISK_MODEL}" | sed "s/[[:space:]]/_/g")

    my_banner "Testing : ${DISK_MODEL} (${disk_dev})";


    ####
    #### IOPING BENCH
    ####

    info "Test ${test_number}/${test_count}: ioping -D -WWW -c ${ioping_count} ${disk_dev}"

    #Create tmpfile to parse after
    tmpFile=$(mktemp "/tmp/ioping_${DISK_MODEL_NO_SPACE}.XXXX")

    if [[ ${verbose} -eq 0 ]]; then
	"${IOPING}" -D -WWW -c "${ioping_count}" "${disk_dev}" | tail -n 2 > "${tmpFile}"
    else
	echo ""
	"${IOPING}" -D -WWW -c "${ioping_count}" "${disk_dev}" | tee "${tmpFile}"
    fi

    #1 requests completed in 366 us, 4.78 k iops, 18.7 MiB/s
    time_and_unit=($(cat "${tmpFile}" | sed -n "s|.* requests completed in \(.*\) \(.*\), .* iops, .*|\1 \2|gp"))
    if [ ${#time_and_unit[@]} -eq 2 ]; then
	case "${time_and_unit[1]}" in
	    "us")  time=${time_and_unit[0]};;
	    "ms")  time=$(echo "scale=0;${time_and_unit[0]} * 1000" | ${BC} -l);;
	    "s")   time=$(echo "scale=0;${time_and_unit[0]} * 1000 * 1000" | ${BC} -l);;
	    "min") time=$(echo "scale=0;${time_and_unit[0]} * 1000 * 1000 * 60" | ${BC} -l);;
	    *)   warn "Cannot parse ioping time1";;
	esac
    else
	warn "Cannot parse ioping time";
    fi

    #1 requests completed in 366 us, 4.78 k iops, 18.7 MiB/s
    iops_and_unit=($(cat "${tmpFile}" | sed -n "s|.* requests completed in .*, \([0-9\.]*\) \(.*\)iops.*|\1 \2|gp"))
    if [ ${#iops_and_unit[@]} -eq 2 ] || [ ${#iops_and_unit[@]} -eq 1 ]; then
	case "${iops_and_unit[1]}" in
	    "")    iops=${iops_and_unit[0]};;
	    "k")  iops=$(echo "scale=0;(${iops_and_unit[0]} * 1000)/1" | ${BC});;
	    *)     warn "Cannot parse ioping iops";;
	esac
    else
	warn "Cannot parse ioping iops";
    fi

    #1 requests completed in 366 us, 4.78 k iops, 18.7 MiB/s
    bw_and_unit=($(cat "${tmpFile}" | sed -n "s|.* requests completed in .*, .*iops, \([0-9\.]*\) \([a-zA-Z]*B\)/s.*|\1 \2|gp"))
    if [ ${#bw_and_unit[@]} -eq 2 ]; then
	case "${bw_and_unit[1]}" in
	    "B")   bw=${bw_and_unit[0]}
		   bw_text=$(echo "scale=3;(${bw_and_unit[0]} / 1000) / 1000" | ${BC} -l)
		   ;;
	    "KiB")  bw=$(echo "scale=0;${bw_and_unit[0]} * 1000" | ${BC} -l)
		    bw_text=$(echo "scale=3;(${bw_and_unit[0]} / 1000)" | ${BC} -l)
		    ;;
	    "MiB")  bw=$(echo "scale=0;${bw_and_unit[0]} * 1000 * 1000" | ${BC} -l)
		    bw_text=$(echo "scale=3;(${bw_and_unit[0]})" | ${BC} -l)
		    ;;
	    *)     warn "Cannot parse ioping bw";;
	esac
    else
	warn "Cannot parse ioping bw";
    fi

    #min/avg/max/mdev = 209 us / 209 us / 209 us / 0 us
    latency_and_unit=($(cat "${tmpFile}" | sed -n "s|min/avg/max/mdev = \([0-9\.]*\) \([a-zA-Z]*\) / \([0-9\.]*\) \([a-zA-Z]*\) / \([0-9\.]*\) \([a-zA-Z]*\) / \([0-9\.]*\) \([a-zA-Z]*\)|\1 \2 \3 \4 \5 \6 \7 \8|gp"))
    if [ ${#latency_and_unit[@]} -eq 8 ]; then
	case "${latency_and_unit[1]}" in
	    "us")   min=${latency_and_unit[0]};;
	    "ms")   min=$(echo "scale=0;${latency_and_unit[0]} * 1000" | ${BC} -l);;
	    "msec") min=$(echo "scale=0;${latency_and_unit[0]} * 1000" | ${BC} -l);;
	    *)      warn "Cannot parse ioping min latency";;
	esac

    	case "${latency_and_unit[3]}" in
	    "us")   avg=${latency_and_unit[2]};;
	    "ms")   avg=$(echo "scale=0;${latency_and_unit[2]} * 1000" | ${BC} -l);;
	    "msec") avg=$(echo "scale=0;${latency_and_unit[2]} * 1000" | ${BC} -l);;
	    *)      warn "Cannot parse ioping avg latency";;
	esac

    	case "${latency_and_unit[5]}" in
	    "us")   max=${latency_and_unit[4]};;
	    "ms")   max=$(echo "scale=0;${latency_and_unit[4]} * 1000" | ${BC} -l);;
	    "msec") max=$(echo "scale=0;${latency_and_unit[4]} * 1000" | ${BC} -l);;
	    *)      warn "Cannot parse ioping max latency";;
	esac

	case "${latency_and_unit[7]}" in
	    "us")   mdev=${latency_and_unit[6]};;
	    "ms")   mdev=$(echo "scale=0;${latency_and_unit[6]} * 1000" | ${BC} -l);;
	    "msec") mdev=$(echo "scale=0;${latency_and_unit[6]} * 1000" | ${BC} -l);;
	    *)      warn "Cannot parse ioping mdev latency";;
	esac
    else
	warn "Cannot parse ioping latency";
    fi
    disk_results+=("$(printf "Result %6s: ioping       : BW = ${GREEN}%7.2f %s${WHITE}, IOPS(min/max/avg/stdev) = ${GREEN}%6s / %6s / %6.0f / %6s${WHITE}, Latency min ${GREEN}${min}us${WHITE} / avg ${GREEN}${avg}us${WHITE} / max ${GREEN}${max}us${WHITE} / mdev ${GREEN}${mdev}us${WHITE}" "${test_number}/${test_count}" "${bw_text}" "MiB" "-" "-" "${iops}" "-")")

    IOPING_RESULT="${time};${iops};${bw};${min};${avg};${max};${mdev};"
    test_number=$((test_number+1))
    rm "${tmpFile}"

    ####
    #### FIO BENCH
    ####

    declare fio_csv=()

    for ioengine in "${ioengine_array[@]}"; do
        for rw in "${rw_array[@]}"; do
	    for job in "${jobs_array[@]}"; do
	        for iodepth in "${iodepth_array[@]}"; do
		    for sync in "${sync_array[@]}"; do
		        for direct in "${direct_array[@]}"; do
			    for bs in "${bs_array[@]}"; do
			        for runtime in "${runtime_array[@]}"; do

				    #Create tmpfile to parse after
				    tmpFile=$(mktemp "/tmp/fio_${DISK_MODEL_NO_SPACE}.XXXX")

				    fio_test_name="${disk_dev},disk_model=${DISK_MODEL}"

				    info "Test ${test_number}/${test_count}: FIO  with following options:" "fio --filename=${disk_dev} --ioengine=${ioengine}--direct=${direct} --sync=${sync} --rw=${rw} --bs=${bs} --numjobs=${job} --iodepth=${iodepth} --runtime=${runtime} --time_based --group_reporting"

				    if [ ${verbose} -eq 0 ]; then
				        "${FIO}" --filename="${disk_dev}" --ioengine="${ioengine}" --direct="${direct}" --sync="${sync}" --rw="${rw}" --bs="${bs}" --numjobs="${job}" --iodepth="${iodepth}" --runtime="${runtime}" --time_based --group_reporting --name="${fio_test_name}" > "${tmpFile}"
				    else
				        echo ""
				        "${FIO}" --filename="${disk_dev}" --ioengine="${ioengine}" --direct="${direct}" --sync="${sync}" --rw="${rw}" --bs="${bs}" --numjobs="${job}" --iodepth="${iodepth}" --runtime="${runtime}" --time_based --group_reporting --name="${fio_test_name}" | tee "${tmpFile}"
				        echo ""
				    fi

				    #iops        : min=10540, max=10994, avg=10794.67, stdev=232.00, samples=3
				    iops_min=$(cat "${tmpFile}" | sed -n "s|.*iops .*: min=\([^,]*\), max=\([^,]*\), avg=\([^,]*\), stdev=\([^,]*\),.*|\1|gp");
				    iops_max=$(cat "${tmpFile}" | sed -n "s|.*iops .*: min=\([^,]*\), max=\([^,]*\), avg=\([^,]*\), stdev=\([^,]*\),.*|\2|gp");
				    iops_avg=$(cat "${tmpFile}" | sed -n "s|.*iops .*: min=\([^,]*\), max=\([^,]*\), avg=\([^,]*\), stdev=\([^,]*\),.*|\3|gp");
				    iops_dev=$(cat "${tmpFile}" | sed -n "s|.*iops .*: min=\([^,]*\), max=\([^,]*\), avg=\([^,]*\), stdev=\([^,]*\),.*|\4|gp");

				    #   WRITE: bw=39.6MiB/s (41.5MB/s), 39.6MiB/s-39.6MiB/s (41.5MB/s-41.5MB/s), io=79.3MiB (83.1MB), run=2001-2001msec
				    bw_and_unit=($(cat "${tmpFile}" | sed -n "s|.* bw=\([0-9\.]*\)\([A-Za-z]*\)/s (\([0-9\.]*\)\([A-Za-z]*\)/s).*|\1 \2|gp"))

				    if [ ${#bw_and_unit[@]} -eq 2 ]; then
					bw_raw=${bw_and_unit[0]}
					bw_text="MiB"
				        case "${bw_and_unit[1]}" in
                                            "B")   bw=$(echo "scale=2;(${bw_raw} / 1024) / 1024" | ${BC} -l); bw_b_per_s=$(echo "scale=0;${bw_raw} * 1 / 1" | ${BC} -l);                 ;;
                                            "KiB") bw=$(echo "scale=2;${bw_raw} / 1024" | ${BC} -l)           bw_b_per_s=$(echo "scale=0;${bw_raw} * 1024 / 1" | ${BC} -l)               ;;
                                            "MiB") bw=$(echo "scale=2;${bw_raw} * 1" | ${BC} -l)              bw_b_per_s=$(echo "scale=0;${bw_raw} * 1024 * 1024 / 1" | ${BC} -l)        ;;
                                            "GiB") bw=$(echo "scale=2;${bw_raw} * 1024" | ${BC} -l)           bw_b_per_s=$(echo "scale=0;${bw_raw} * 1024 * 1024 * 1024 / 1" | ${BC} -l) ;;
					    *)     warn "Cannot parse fio bw";;
				        esac
				    else
				        warn "Cannot parse fio bw";
				    fi

				    #/dev/xvdb,disk_model=: (g=0): rw=randread, bs=(R) 4096B-4096B, (W) 4096B-4096B, (T) 4096B-4096B, ioengine=posixaio, iodepth=1
				    #rw=$(      cat "${tmpFile}" | sed -n "s|.*rw=\([^,]*\), bs=\(.*\), ioengine=\([^,]*\), iodepth=\(.*\)$|\1|gp"|head -n 1);
				    #bs=$(      cat "${tmpFile}" | sed -n "s|.*rw=\([^,]*\), bs=\(.*\), ioengine=\([^,]*\), iodepth=\(.*\)$|\2|gp"|head -n 1);
				    #ioengine=$(cat "${tmpFile}" | sed -n "s|.*rw=\([^,]*\), bs=\(.*\), ioengine=\([^,]*\), iodepth=\(.*\)$|\3|gp"|head -n 1);
				    #iodepth=$( cat "${tmpFile}" | sed -n "s|.*rw=\([^,]*\), bs=\(.*\), ioengine=\([^,]*\), iodepth=\(.*\)$|\4|gp"|head -n 1);

				    rm "${tmpFile}"

				    fio_csv+=("${direct};${sync};${job};${bs};${ioengine};${iodepth};${rw};${iops_min};${iops_max};${iops_avg};${iops_dev};${bw_b_per_s};${runtime};")
				    disk_results+=("$(printf "Result %6s: fio %-9s: BW = ${GREEN}%7.2f %s${WHITE}, IOPS(min/max/avg/stdev) = ${GREEN}%6.0f / %6.0f / %6.0f / %6.0f${WHITE}\n" " ${test_number}/${test_count}" "$rw" "${bw}" "${bw_text}" "${iops_min}" "${iops_max}" "${iops_avg}" "${iops_dev}")")

				    test_number=$((test_number+1))
			        done
			    done
		        done
		    done
	        done
	    done
        done
    done

    if [ ${export_to_file} -eq 1 ]; then
	MODEL_CSV_HEADER="disk_model;disk_size;disk_size_unit;disk_firmware_version;"
	FIO_CSV_HEADER="fio_io_direct;fio_io_sync;fio_nb_jobs;fio_bs;fio_ioengine;fio_iodepth;fio_rw;fio_iops_min;fio_iops_max;fio_iops_avg;fio_iops_stdev;fio_bw (B/s);fio_runtime (s);"
	IOPING_CSV_HEADER="ioping_time (us);ioping_iops;ioping_bw (B/s);ioping_min_latency (us);ioping_avg_latency (us);ioping_max_latency (us);ioping_mdev_latency (us);"

	CSV_HEADER=${MODEL_CSV_HEADER}${FIO_CSV_HEADER}${IOPING_CSV_HEADER}

	output_file="${RESULT_FOLDER}/${DISK_MODEL_NO_SPACE}_${DISK_SIZE[0]}${DISK_SIZE[1]}_${DISK_FIRMWARE}_${disk_number}.csv"
	info "Write results for ${DISK_MODEL} in ${output_file}"
	echo "${CSV_HEADER}" > "${output_file}"
	for fio_line in "${fio_csv[@]}"; do
	    echo "${DISK_MODEL};${DISK_SIZE[0]};${DISK_SIZE[1]};${DISK_FIRMWARE};${fio_line}${IOPING_RESULT}" >> "${output_file}"
	done
    fi

    echo ""
    for result in "${disk_results[@]}"; do
	info "${result}"
    done
    echo ""

done
