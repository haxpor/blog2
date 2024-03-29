#!/bin/bash
# main management script to do various operations
#
# make <operation> [options]
#
# See print_help() function for more information on usage.

# check basic requirement needed to properly run the program
# Depend on the following program
# 1. firefox or google-chrome-stable (configurable via `BROWSER` variable)
# 2. pandoc
# 3. inotifywait
# if it detects a missing dependency then it will print out and exit immediately.
check_requirement() {
	# the list of application the script depends on
	dep_app_array=(pandoc inotifywait)
    
	for app in "${dep_app_array[@]}"
	do
		which "$app" 2>&1 > /dev/null
		if [ $? -ne 0 ]; then
			echo "Error! Install '$app' first before proceed further."
			exit 1
		fi
	done
}

# always check for dependency first before doing anything
check_requirement

CMD=$1

# build directory for processed .txt file as .html
BUILD_DIR=build

# browser to open to see the changes of editing .html file
BROWSER=google-chrome-stable
# optional parameters to launch BROWSER, leave it empty if there's none
BROWSER_PARAMS="--enable-features=WebUIDarkMode --force-dark-mode"

# fixed published date in source files
PUBLISHED_DATE_PATTERN="First published on "

# colors
YELLOW='\033[93m'
GREEN='\033[0;32m'
NC='\033[0m'

# ignored pattern
IGNORED_PATTERN="*_IGNORED.txt"

# mathjax
MATHJAX_URL="https://cdn.mathjax.org/mathjax/latest/MathJax.js?config=TeX-AMS_CHTML-full"

print_help() {
	echo "Management script"
	echo "Usage: make <operation> [options]"
	echo ""
	echo "<operation> is available as follows"
	echo "  new   - Create a new post, or continue Editing if a file exists."
	echo ""
	echo "          Usage: new src/<filename.txt>"
	echo ""
	echo "          This will create a new post .txt at src/ directory if a file not exist, otherwise"
	echo "          ask to overwrite or continue editing from existing content, then execute"
	echo "          'inotifywait' for automatically update changes then write as output .html at"
	echo "          posts/ directory, then finally open a browser tab using firefox."  
	echo ""
	echo "  build [<post-no>,all,index]   - build .txt source file into .html"
	echo ""
	echo "          Usage: build <post-no>"
	echo "                 build a specific post No. then copy, implicitly build index."
	echo ""
	echo "          Usage: build all"
	echo "                 build all src/*.txt file into posts/*.html, and index.txt into index.html"
	echo ""
	echo "          Usage: build index"
	echo "                 build only index.txt into index.html"
	echo ""
	echo "  list  - List all of the posts"
	echo ""
	echo "          Usage: list [--no-format]"
	echo ""
	echo "          --no-format no aligned format, suitablefor small screen width."
	echo ""
	echo "  clean - Clean all files inside build directory (build/)"
	echo ""
}

build_index() {
	# copy template index file into file we will be editing
	cp -p index_template.txt /tmp/blog2_index.txt

	# source all titles from src/*.txt into index.txt
	find src -type f -name "*.txt" ! -name ${IGNORED_PATTERN} -print0 | xargs --null ls -1 | sort -V | while read file
	do
		# get filename without extension
		html_fname=$(basename "$file")
		# replace empty space with underscore
		html_fname=${html_fname// /_}
		# replace to use .html extension
		html_fname=${html_fname%%.*}.html

		title=`head -1 $file`
        
		echo "* [$title]($html_fname)" >> /tmp/blog2_index.txt

		printf "source title from %40s\n" "$file"
	done

	# get index's title text
	index_title=`head -1 /tmp/blog2_index.txt`

	# process into html
	pandoc -c belug1.css -H header.html -B before-min.html -A after-min.html /tmp/blog2_index.txt --metadata pagetitle="$index_title" -o $BUILD_DIR/index.html

	# show error messasge when things went wrong
	if [ $? -ne 0 ]; then
		echo "Error building index.html"
		exit 1
	fi
}

build_cpsupportfiles() {
	cp -p belug1.css $BUILD_DIR/belug1.css
	cp -rp assets $BUILD_DIR/assets
}

list_allposts() {
	find src -type f -name "*.txt" ! -name ${IGNORED_PATTERN} -print0 | xargs --null ls -1 | sort -V | while read file
	do
		# find published date as wrote (fixed pattern) inside the source file
		pub_string=$(tail "$file" | grep "$PUBLISHED_DATE_PATTERN");
		pub_string=${pub_string:19:-1};

		# get title string from source file
		title=$(head -1 "$file")

		if [ "$1" == "--no-format" ]; then
			printf "%s ${YELLOW}%s${NC} ${GREEN}[${NC}%s${GREEN}]${NC}\n" "$file" "$title" "$pub_string"
		else
			printf "%60s ${YELLOW}%60s${NC} ${GREEN}[${NC}%15s${GREEN}]${NC}\n" "$file" "$title" "$pub_string"
		fi

	done
}

if [ -z "$CMD" ] || [ "$CMD" == "--help" ]; then
	print_help
	exit 1
fi

if [ "$CMD" == "new" ]; then
	# get the filename parameter
	if [ -z "$2" ]; then
		echo "Missing <filename.txt> parameter"
		echo "Usage: make new <filename.txt>"
		exit 1
	fi

	# cut prefix src/ part
	file_name=`echo "$2" | cut -d/ -f 2`

	# if all ok
	# check if file extension is exactly only 'txt'
	file_extension="${file_name##*.}"
	if [ "${file_extension}" != "txt" ]; then
		echo "Input file can only be .txt"
		exit 1
	fi

	# check if there's existing source file, to avoid overwriting
	if [ -f "src/$file_name" ]; then
		echo "Target source file 'src/$file_name' exists"
		read -p "Overwrite [N/y]: " confirm

		# not overwrite
		# convert to smaller case
		cconfirm=`echo "$confirm" | tr '[:upper:]' '[:lower:]'`
	# if not exist, then create an empty template file
	else
		echo "Your Title Here
=========================================================" > "src/$file_name"
		echo "Created 'src/$file_name'"
	fi

	# if confirmed to overwrite
	if [ "$cconfirm" == "y" ]; then
		# write file to src/
		printf "Your Post Title\n---------" > "src/$file_name" && echo "Wrote source file 'src/$file_name'"
		# show error message when things went wrong
		if [ $? -ne 0 ]; then
			echo "Error: Can't wrote file"
			exit 1
		fi
	fi

	# create build directory if not yet exist
	if [ ! -d $BUILD_DIR ]; then
		mkdir $BUILD_DIR
		echo "Created $BUILD_DIR directory"
	fi

	# copy supporting files
	echo "Copy supporting files into $BUILD_DIR"
	build_cpsupportfiles

	# get title string from source file
	title=$(head -1 "src/$file_name")

	# pre-convert so users can see the result of .html now
	pandoc --mathjax=$MATHJAX_URL -c belug1.css -H header.html -B before.html -A after.html "src/$file_name" --metadata pagetitle="$title" -o "$BUILD_DIR/${file_name%%.*}.html"

	which ${BROWSER} 2>&1 > /dev/null
	if [ $? -eq 0 ]; then
		${BROWSER} ${BROWSER_PARAMS} $BUILD_DIR/${file_name%%.*}.html
	fi

	# wait and listen to file changes event for writing.
	# this is a blocking call infinitely wait until exit this process (theoridically after user finishes editing the post)
	# note: don't try to execute this in the background, it's mess to clean up later
	while inotifywait -e modify "src/$file_name" || true; do pandoc --mathjax=$MATHJAX_URL -c belug1.css -H header.html -B before.html -A after.html "src/$file_name" --metadata pagetitle="$title" -o "$BUILD_DIR/${file_name%%.*}.html" ; done
	# show error messasge when things went wrong
	if [ $? -ne 0 ]; then
		echo "Can't listen to file changes event"
		exit 1
	fi

	# re-build all build automatically
elif [ "$CMD" == "build" ]; then
	# create build directory if not yet exist
	if [ ! -d $BUILD_DIR ]; then
		mkdir $BUILD_DIR
		echo "Created $BUILD_DIR directory"
	fi

	# get what to build
	# build for specific post#no.
	if [ -z "$2" ]; then
		echo "Empty parameters"
		print_help
	elif ! [[ -n ${2//[0-9]/} ]]; then
		echo "Build for post $2"

		# file not exist
		if [ ! -f src/$2_*.txt ]; then
			echo "Target file doesn't exist"
			exit 1
		fi

		echo "This will build only for '$(ls src/$2_*.txt)'"
		# get only filename
		target_file="$(basename `ls src/$2_*.txt`)"

		# just for consistency with logic code in "build" case
		# TODO: probably need to refactor this into function...
		find src -type f -name "$target_file" ! -name ${IGNORED_PATTERN} -print0 | xargs --null ls -1 | sort -V | while read file
		do
			# get output filename without extension
			oname=$(basename "$file")
			# replace empty space with underscore
			oname=${oname// /_}
			# replace to use .html extension
			oname=${oname%%.*}.html

			# find published date as wrote (fixed pattern) inside the source file
			pub_string=$(tail "$file" | grep "$PUBLISHED_DATE_PATTERN");
			pub_string=${pub_string:19:-1};

			printf "%40s  ${GREEN}[${NC}%15s${GREEN}]${NC}\n" "$file" "$pub_string"

			# get title string from source file
			title=$(head -1 "$file")

			pandoc --mathjax=$MATHJAX_URL -c belug1.css -H header.html -B before.html -A after.html "$file" --metadata pagetitle="$title" -o "$BUILD_DIR/${oname}";

			# show error messasge when things went wrong
			if [ $? -ne 0 ]; then
				echo "Error building $file"
				exit 1
			fi
		done

		echo "Build index.html"
		build_index

		echo "Copy supporting files into $BUILD_DIR"
		build_cpsupportfiles

	# build index.html page
	elif [ "$2" == "index" ]; then
		# check if the directory is empty
		if [ ! "$(ls -A src)" ]; then
			echo "src/ is empty"
			exit 0
		fi

		echo "Build index.html"
		build_index

		echo "Copy supporting files into $BUILD_DIR"
		build_cpsupportfiles
	# build for all posts
	elif [ "$2" == "all" ]; then
		echo "Build all posts"

		# check if the directory is empty
		if [ ! "$(ls -A src)" ]; then
			echo "src/ is empty"
			exit 0
		fi

		find src -type f -name "*.txt" ! -name ${IGNORED_PATTERN} -print0 | xargs --null ls -1 | sort -V | while read file
		do
			# get output filename without extension
			oname=$(basename "$file")
			# replace empty space with underscore
			oname=${oname// /_}
			# replace to use .html extension
			oname=${oname%%.*}.html

			# find published date as wrote (fixed pattern) inside the source file
			pub_string=$(tail "$file" | grep "$PUBLISHED_DATE_PATTERN");
			pub_string=${pub_string:19:-1};

			printf "%40s  ${GREEN}[${NC}%15s${GREEN}]${NC}\n" "$file" "$pub_string"

			# get title string from source file
			title=$(head -1 "$file")

			pandoc --mathjax=$MATHJAX_URL -c belug1.css -H header.html -B before.html -A after.html "$file" --metadata pagetitle="$title" -o "$BUILD_DIR/${oname}";

			# show error messasge when things went wrong
			if [ $? -ne 0 ]; then
				echo "Error building $file"
				exit 1
			fi
		done

		echo "Build index.html"
		build_index

		echo "Copy supporting files into $BUILD_DIR"
		build_cpsupportfiles

	# anything else
	else
		echo "Not recognize parameters"
		print_help
	fi
# clean build directory
elif [ "$CMD" == "clean" ]; then
	rm -rf $BUILD_DIR/* && echo "Clean $BUILD_DIR"
# list all posts
elif [ "$CMD" == "list" ]; then
	list_allposts $2
# otherwise not match any commands
else
	print_help
fi
