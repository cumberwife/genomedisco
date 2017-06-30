
code=/srv/gsfs0/projects/snyder/oursu/software/git/public_genomedisco/genomedisco
bashrc=${code}/scripts/bashrc_genomedisco
source ${bashrc}
data=/ifs/scratch/oursu/3d/paper/2017-06-08/LA
outdir=${data}/reproducibility
mkdir -p ${data}/datasets

reads_location=/srv/gsfs0/projects/kundaje/users/oursu/3d/LA/merged_nodups/data
bashrc_3Dutils=/srv/gsfs0/projects/snyder/oursu/software/git/genome_utils/3Dutils/bashrc_3D

step=$1

if [[ ${step} == "nodes" ]];
then
    for res in 500000 40000 10000;
    do
	source ${bashrc_3Dutils}
	mkdir -p ${data}/datasets/nodes
	bedtools makewindows -i winnum -w ${res} -s ${res} -g ${chrSizes} | awk '{print $1"\t"$2"\t"$3"\t"$2}' | gzip > ${data}/datasets/nodes/nodes.${res}.gz
    done
fi

if [[ ${step} == "multiple_resolutions" ]];
then
    for res in 500000 40000 10000;
    do
	for dataset_number in {1..83};
	do
	    dataset="HIC"$(echo "00${dataset_number}" | sed 's/.*\(...\)/\1/')
	    echo ${dataset}
	    reads=$(ls ${reads_location}/*_${dataset}_merged_nodups.txt.gz)
	    new_file=${data}/datasets/res${res}/${dataset}.res${res}.gz
	    mkdir -p $(dirname ${new_file})
	    s=${new_file}.sh
	    echo "source ${bashrc_3Dutils}" > ${s}
	    echo "LA_reads_to_n1n2value_bins.sh ${reads} ${new_file} 30 intra ${res}" >> ${s}
	    chmod 755 ${s}
	    qsub -l h_vmem=100G -o ${s}.o -e ${s}.e ${s}
	done
    done
fi

if [[ ${step} == "metadata" ]];
then
    for res in 500000 40000 10000;
    do
	#metadata samples
	rm ${data}/datasets/res${res}/metadata.res${res}.samples
	for dataset_number in {1..83};
        do
            dataset="HIC"$(echo "00${dataset_number}" | sed 's/.*\(...\)/\1/')
	    echo "${dataset}delim${data}/datasets/res${res}/${dataset}.res${res}.gz" | sed 's/delim/\t/g' >> ${data}/datasets/res${res}/metadata.res${res}.samples
	done

	#metadata pairs
	metadata_pairs=${data}/datasets/res${res}/metadata.res${res}.pairs
	rm ${metadata_pairs}*
	#odds
	for data1 in $(zcat -f ${data}/datasets/res${res}/metadata.res${res}.samples | cut -f1 | sed -n 'p;n');
	do
	    for data2 in $(zcat -f ${data}/datasets/res${res}/metadata.res${res}.samples | cut -f1 | sed -n 'p;n');
	    do
		echo "${data1}delim${data2}" | sed 's/delim/\t/g' >> ${metadata_pairs}.tmp
	    done
	done
	#evens
	for data1 in $(zcat -f ${data}/datasets/res${res}/metadata.res${res}.samples | cut -f1 | sed -n 'n;p');
        do
            for data2 in $(zcat -f ${data}/datasets/res${res}/metadata.res${res}.samples | cut -f1 | sed -n 'n;p');
            do
                echo "${data1}delim${data2}" | sed 's/delim/\t/g' >> ${metadata_pairs}.tmp
            done
        done

	${mypython} ${code}/scripts/orderpairs.py --file ${metadata_pairs}.tmp --out ${metadata_pairs}.tmp2
	cat ${metadata_pairs}.tmp2 | sort | uniq | awk '{if ($1!=$2) print $0}' > ${metadata_pairs}
	rm ${metadata_pairs}.tmp*
    done
fi

if [[ ${step} == "split" ]];
then
    for res in 40000 10000;
    do
	metadata_samples=${data}/datasets/res${res}/metadata.res${res}.samples
	nodes=${data}/datasets/nodes/nodes.${res}.gz
	outdir=${data}/reproducibility/res${res}
	${mypython} ${code}/genomedisco/__main__.py split --metadata_samples ${metadata_samples} --datatype hic --nodes ${nodes} --running_mode sge --outdir ${outdir} --concise_analysis
    done
fi

if [[ ${step} == "run" ]];
then
    for res in 40000;#500000 40000 10000;
    do
	metadata_pairs=${data}/datasets/res${res}/metadata.res${res}.pairs
	outdir=${data}/reproducibility/res${res}
    ${mypython} ${code}/genomedisco/__main__.py reproducibility --metadata_pairs ${metadata_pairs} --datatype hic --tmin 1 --tmax 5 --outdir ${outdir} --norm sqrtvc --running_mode sge --concise_analysis
    done
fi

if [[ ${step} == "compile_full_scores" ]];
then
    for res in 40000;
    do
	for chromo in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 X;
	do
	    outdir=${data}/reproducibility/res${res}
	    cat ${outdir}/results/genomedisco/*/*chr${chromo}.*scoresByStep.txt | grep -v "#" > ${outdir}/results/genomedisco/summary/res${res}.chr${chromo}.scoresByStep.txt 
	done
    done
fi

if [[ ${step} == "report" ]];
then
    for res in 40000; 
    do
        metadata_pairs=${data}/datasets/res${res}/metadata.res${res}.pairs
	cat ${metadata_pairs} | head -n10 > ${metadata_pairs}.head
        outdir=${data}/reproducibility/res${res}
	${mypython} ${code}/genomedisco/__main__.py visualize --metadata_pairs ${metadata_pairs}.head --tmin 1 --tmax 5 --outdir ${outdir} 
	mkdir -p ${outdir}/results/genomedisco/summary
	cat ${outdir}/results/genomedisco/*/genomewide_scores.* | head -n1 > ${outdir}/results/genomedisco/summary/genomedisco.res${res}.txt
        cat ${outdir}/results/genomedisco/*/genomewide_scores.* | grep -v "#" >> ${outdir}/results/genomedisco/summary/genomedisco.res${res}.txt
    done
fi

if [[ ${step} == "score_again" ]];
then
    memo=" -l h_vmem=50G -l hostname=scg3* "
    for res in 40000;
    do
        for pair in $(ls ${data}/reproducibility/res${res}/scripts/reproducibility/);
        do
	    for chromo in 1 2 3; #4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 X;
            do
                scorefile=${data}/reproducibility/res${res}/results/genomedisco/${pair}/chr${chromo}.${pair}.scoresByStep.txt
                s=${data}/reproducibility/res${res}/scripts/reproducibility/${pair}/chr${chromo}.${pair}.genomedisco.sh
                #if [ ! -f ${scorefile} ];
		if [[ $(cat ${pair}/chr${chromo}.${pair}.scoresByStep.txt | grep NA | wc -l) > 0 ]];
                then
		    echo ${s}
                    qsub ${memo} -o ${s}.o -e ${s}.e ${s}
                fi
            done
        done
    done
fi



if [[ ${step} == "scores" ]];
then
    outscores=${outdir}/plots/disco.scores.txt
    mkdir -p ${outdir}/plots
    zcat -f ${outdir}/results/*/chr18*.scores.txt | awk '{print $1"_"$2"\t"$3}' | sort -k1b,1 > ${outscores}.scores
    zcat -f ${outdir}/results/*/chr18*.datastats.txt | awk '{print $1"_"$2"\t"$3"\t"$4"\t"$5"\t"$6"\t"$7}' | sort -k1b,1 > ${outscores}.stats
    join -1 1 -2 1 ${outscores}.scores ${outscores}.stats | sed 's/ /\t/g' | sed 's/_/\t/g'  > ${outscores}
    rm ${outscores}.scores ${outscores}.stats 
    echo ${outscores}
fi

if [[ ${step} == 'others' ]];
then
    codebase=/srv/gsfs0/projects/snyder/oursu/software/git/public_genomedisco/genomedisco
    bashrc=${codebase}/paper_analysis/2017-06-08/all_methods/methods_bashrc
    source ${bashrc}
    chrSizes=${codebase}/paper_analysis/2017-06-08/all_methods/chrSizes
    #resolution=40000
    

    for res in 40000;
    do
	resolution=${res}
        metadata_pairs=${data}/datasets/res${res}/metadata.res${res}.pairs
        outdir=${data}/reproducibility/res${res}
	metadata_samples=${data}/datasets/res${res}/metadata.res${res}.samples
	for chromosome in $(zcat -f ${outdir}/data/metadata/chromosomes.gz | sed 's/\n/ /g' | sed 's/chr//g');
	do
	    echo ${chromosome}
	    if [[ ${chromosome} == '5' ]];
	    then
		echo ${chromosome}
		bins=${outdir}/data/nodes/nodes.chr${chromosome}.gz
		samples=${metadata_samples}.chr${chromosomes}
		rm ${samples}
		for sample in $(zcat -f ${metadata_samples} | cut -f1);
		do
		    echo "${sample}delim${outdir}/data/edges/${sample}/${sample}.chr${chromosome}.gz" | sed 's/delim/\t/g' >> ${samples}
		done
		echo "code"
		echo ${code}
		parameters=${code}/example_parameters.txt
		action=compute
		${code}/compute_reproducibility.sh -o ${outdir} -n ${bins} -s ${samples} -p ${metadata_pairs} -a compute -b ${bashrc} -r ${resolution} -m ${parameters} -j sge -c chr${chromosome}
	    fi
	done
    done
    
fi