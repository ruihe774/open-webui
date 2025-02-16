<script lang="ts">
	import { toast } from 'svelte-sonner';
	import { DropdownMenu } from 'bits-ui';
	import { getContext } from 'svelte';

	import fileSaver from 'file-saver';
	const { saveAs } = fileSaver;

	import jsPDF from 'jspdf';
	import html2canvas from 'html2canvas-pro';

	import MarkdownIt from "markdown-it";
	import MarkdownItVPlugin from "markdown-it-v";
	import type { MarkdownItV, StreamDom } from "markdown-it-v";

	import { downloadChatAsPDF } from '$lib/apis/utils';
	import { copyToClipboard, createMessagesList } from '$lib/utils';

	import {
		showOverview,
		showControls,
		showArtifacts,
		mobile,
		temporaryChatEnabled,
		theme
	} from '$lib/stores';
	import { flyAndScale } from '$lib/utils/transitions';

	import Dropdown from '$lib/components/common/Dropdown.svelte';
	import Tags from '$lib/components/chat/Tags.svelte';
	import Map from '$lib/components/icons/Map.svelte';
	import Clipboard from '$lib/components/icons/Clipboard.svelte';
	import AdjustmentsHorizontal from '$lib/components/icons/AdjustmentsHorizontal.svelte';
	import Cube from '$lib/components/icons/Cube.svelte';
	import { getChatById } from '$lib/apis/chats';

	const i18n = getContext('i18n');

	type VirtualNode = StreamDom["currentNode"];
	const md = MarkdownIt().use(MarkdownItVPlugin) as unknown as MarkdownItV;

	export let shareEnabled: boolean = false;
	export let shareHandler: Function;
	export let downloadHandler: Function;

	// export let tagHandler: Function;

	export let chat;
	export let onClose: Function = () => {};

	const getChatAsText = () => {
		const history = chat.chat.history;
		const messages = createMessagesList(history, history.currentId);
		const chatText = messages.reduce((a, message, i, arr) => {
			return `${a}### ${message.role.toUpperCase()}\n${message.content}\n\n`;
		}, '');

		return chatText.trim();
	};

	const getChatAsHTML = () => {
		const history = chat.chat.history;
		const messages = createMessagesList(history, history.currentId);
		return messagesToHTML(messages)
	}

	const downloadTxt = async () => {
		const chatText = getChatAsText();

		let blob = new Blob([chatText], {
			type: 'text/plain'
		});

		saveAs(blob, `chat-${chat.chat.title}.txt`);
	};

	const downloadPdf = async () => {
		const containerElement = document.getElementById('messages-container');

		if (containerElement) {
			try {
				const isDarkMode = document.documentElement.classList.contains('dark');

				console.log('isDarkMode', isDarkMode);

				// Define a fixed virtual screen size
				const virtualWidth = 800; // Fixed width (adjust as needed)
				// Clone the container to avoid layout shifts
				const clonedElement = containerElement.cloneNode(true);
				clonedElement.classList.add('text-black');
				clonedElement.classList.add('dark:text-white');
				clonedElement.style.width = `${virtualWidth}px`; // Apply fixed width
				clonedElement.style.height = 'auto'; // Allow content to expand

				document.body.appendChild(clonedElement); // Temporarily add to DOM

				// Render to canvas with predefined width
				const canvas = await html2canvas(clonedElement, {
					backgroundColor: isDarkMode ? '#000' : '#fff',
					useCORS: true,
					scale: 2, // Keep at 1x to avoid unexpected enlargements
					width: virtualWidth, // Set fixed virtual screen width
					windowWidth: virtualWidth // Ensure consistent rendering
				});

				document.body.removeChild(clonedElement); // Clean up temp element

				const imgData = canvas.toDataURL('image/png');

				// A4 page settings
				const pdf = new jsPDF('p', 'mm', 'a4');
				const imgWidth = 210; // A4 width in mm
				const pageHeight = 297; // A4 height in mm

				// Maintain aspect ratio
				const imgHeight = (canvas.height * imgWidth) / canvas.width;
				let heightLeft = imgHeight;
				let position = 0;

				// Set page background for dark mode
				if (isDarkMode) {
					pdf.setFillColor(0, 0, 0);
					pdf.rect(0, 0, imgWidth, pageHeight, 'F'); // Apply black bg
				}

				pdf.addImage(imgData, 'PNG', 0, position, imgWidth, imgHeight);
				heightLeft -= pageHeight;

				// Handle additional pages
				while (heightLeft > 0) {
					position -= pageHeight;
					pdf.addPage();

					if (isDarkMode) {
						pdf.setFillColor(0, 0, 0);
						pdf.rect(0, 0, imgWidth, pageHeight, 'F');
					}

					pdf.addImage(imgData, 'PNG', 0, position, imgWidth, imgHeight);
					heightLeft -= pageHeight;
				}

				pdf.save(`chat-${chat.chat.title}.pdf`);
			} catch (error) {
				console.error('Error generating PDF', error);
			}
		}
	};

	const downloadJSONExport = async () => {
		if (chat.id) {
			let chatObj = null;

			if (chat.id === 'local' || $temporaryChatEnabled) {
				chatObj = chat;
			} else {
				chatObj = await getChatById(localStorage.token, chat.id);
			}

			let blob = new Blob([JSON.stringify([chatObj])], {
				type: 'application/json'
			});
			saveAs(blob, `chat-export-${Date.now()}.json`);
		}
	};

	const copyChatToClipboard = async () => {
		return await copyToClipboard(getChatAsText(), getChatAsHTML())
	}

	function messagesToHTML(messages: {
		content: string;
		role: "user" | "assistant";
	}[]) {
		let html = "";
		html += "<article>";
		messages.forEach(({ content, role }) => {
			let responseStart = 0;
			if (role == "user") {
				html += "<section>";
				const questionContent = content;
				const questionDOM = md.render(questionContent);
				collapseSpace(questionDOM);
				html += `<div style="font-style:italic">${questionDOM.toHTML()}</div>`;
			} else if (role == "assistant") {
				html += "<div>";
				if (content.startsWith("<details")) {
					const thinkStart = content.search(/<\/summary>$/m) + 11;
					const thinkEnd = content.search(/^<\/details>/m) - 1;
					responseStart = thinkEnd + 14;
					const thinkContent = content.slice(thinkStart, thinkEnd).replaceAll(
						/^> /gm,
						"",
					);
					const thinkDOM = md.render(thinkContent);
					collapseSpace(thinkDOM);
					html += `<blockquote>${thinkDOM.toHTML()}</blockquote>`;
				}
				const responseContent = content.slice(responseStart);
				const responseDOM = md.render(responseContent);
				collapseSpace(responseDOM);
				removeHr(responseDOM);
				html += `<div>${responseDOM.toHTML()}</div>`;
				html += "</div>";
				html += "</section><hr>";
			} else {
				console.warn(`unknown role ${role}`);
			}
		});
		html = (html.endsWith("<hr>") ? html.slice(0, -4) : html) + "</article>";
		return html;
	}

	function removeHr(sdom: StreamDom) {
		const leaves = Array.from(collectLeafNodes(sdom.currentNode));
		for (const [i, current] of leaves.entries()) {
			if (current.type == "virtual" && current.node.tagName == "hr") {
				const parent = current.node.parent!;
				parent.children[parent.children.indexOf(current.node)] = "";
				const next = leaves[i + 1];
				if (
					next && next.type == "text" && next.parent === parent &&
					next.value == "\n"
				) {
					parent.children[next.index] = "";
				}
			}
		}
	}

	function collapseSpace(sdom: StreamDom) {
		const leaves = Array.from(collectLeafNodes(sdom.currentNode));
		for (const [i, current] of leaves.entries()) {
			const next = leaves[i + 1];
			if (next && current.type == "text" && next.type == "text") {
				processTextPair(current, next);
			}
		}
	}

	function* collectLeafNodes(
		node: VirtualNode | string,
		index: number = 0,
		parent?: VirtualNode,
	): Iterable<
		{
			type: "text";
			parent: VirtualNode | undefined;
			index: number;
			value: string;
		} | { type: "virtual"; node: VirtualNode }
	> {
		if (typeof node == "string") {
			yield { type: "text", parent, index, value: node };
		} else if (node.children.length == 0) {
			yield { type: "virtual", node };
		} else {
			for (const [index, child] of node.children.entries()) {
				yield* collectLeafNodes(child, index, node);
			}
		}
	}

	function processTextPair<
		T extends { parent: VirtualNode | undefined; index: number; value: string },
	>(prevNode: T, nextNode: T) {
		const prevText = [...prevNode.value];
		const nextText = [...nextNode.value];

		const lastNonSpaceIndex = prevText.findLastIndex((char) => char != " ");
		const lastNonSpace = prevText[lastNonSpaceIndex];
		const firstNonSpaceIndex = nextText.findIndex((char) => char != " ");
		const firstNonSpace = nextText[firstNonSpaceIndex];
		if (
			firstNonSpace && lastNonSpace &&
			((isIdeograph(lastNonSpace) || isFullwidthPunct(lastNonSpace)) &&
				(isIdeograph(firstNonSpace) || isNonIdeographicLetter(firstNonSpace) ||
					isNonIdeographicNumeral(firstNonSpace) ||
					isFullwidthPunct(firstNonSpace) || maybeCJKPunct(firstNonSpace)) ||
				(isIdeograph(firstNonSpace) || isFullwidthPunct(firstNonSpace)) &&
				(isIdeograph(lastNonSpace) || isNonIdeographicLetter(lastNonSpace) ||
					isNonIdeographicNumeral(lastNonSpace) ||
					isFullwidthPunct(lastNonSpace) || maybeCJKPunct(lastNonSpace)))
		) {
			prevText.splice(lastNonSpaceIndex + 1);
			nextText.splice(0, firstNonSpaceIndex);
			const newPrev = prevText.join("");
			prevNode.parent!.children[prevNode.index] = newPrev;
			const newNext = nextText.join("");
			nextNode.parent!.children[nextNode.index] = newNext;
		}
	}

	function isIdeograph(char: string) {
		const codePoint = char.codePointAt(0)!;
		return codePoint >= 0x3041 && codePoint <= 0x30FF && !/\p{P}/u.test(char) ||
			codePoint >= 0x31C0 && codePoint <= 0x31EF ||
			codePoint >= 0x31F0 && codePoint <= 0x31FF || /\p{Script=Han}/u.test(char);
	}

	function isEastAsianFullwidth(char: string) {
		const cp = char.codePointAt(0)!;
		return (
			(cp >= 0xFF00 && cp <= 0xFFEF) ||
			(cp >= 0x3000 && cp <= 0x3002) ||
			(cp >= 0xFE30 && cp <= 0xFE4F)
		);
	}

	function isNonIdeographicLetter(char: string) {
		return /\p{L}|\p{M}/u.test(char) && !isIdeograph(char) &&
			!isEastAsianFullwidth(char);
	}

	function isNonIdeographicNumeral(char: string) {
		return /\p{Nd}/u.test(char) && !isEastAsianFullwidth(char);
	}

	function isFullwidthOpeningPunct(char: string) {
		const cp = char.codePointAt(0)!;
		return /\p{Ps}/u.test(char) &&
			(cp >= 0x3000 && cp <= 0x303F || isEastAsianFullwidth(char) ||
				cp == 0x2018 || cp == 0x201C);
	}

	function isFullwidthClosingPunct(char: string) {
		const cp = char.codePointAt(0)!;
		return /\p{Pe}/u.test(char) &&
			(cp >= 0x3000 && cp <= 0x303F || isEastAsianFullwidth(char) ||
				cp == 0x2019 || cp == 0x201D);
	}

	function isFullwidthOtherPunct(char: string) {
		const cp = char.codePointAt(0)!;
		return [
			0x00B7,
			0x2027,
			0x30FB,
			0xFF1A,
			0xFF1B,
			0x3001,
			0x3002,
			0xFF0C,
			0xFF0E,
		].includes(cp);
	}

	function isFullwidthPunct(char: string) {
		return isFullwidthOpeningPunct(char) || isFullwidthClosingPunct(char) ||
			isFullwidthOtherPunct(char);
	}

	function maybeCJKPunct(char: string) {
		return char == "“" || char == "”" || char == "—";
	}
</script>

<Dropdown
	on:change={(e) => {
		if (e.detail === false) {
			onClose();
		}
	}}
>
	<slot />

	<div slot="content">
		<DropdownMenu.Content
			class="w-full max-w-[200px] rounded-xl px-1 py-1.5  z-50 bg-white dark:bg-gray-850 dark:text-white shadow-lg"
			sideOffset={8}
			side="bottom"
			align="end"
			transition={flyAndScale}
		>
			<!-- <DropdownMenu.Item
				class="flex gap-2 items-center px-3 py-2 text-sm  cursor-pointer dark:hover:bg-gray-800 rounded-md"
				on:click={async () => {
					await showSettings.set(!$showSettings);
				}}
			>
				<svg
					xmlns="http://www.w3.org/2000/svg"
					fill="none"
					viewBox="0 0 24 24"
					stroke-width="1.5"
					stroke="currentColor"
					class="size-4"
				>
					<path
						stroke-linecap="round"
						stroke-linejoin="round"
						d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.325.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 0 1 1.37.49l1.296 2.247a1.125 1.125 0 0 1-.26 1.431l-1.003.827c-.293.241-.438.613-.43.992a7.723 7.723 0 0 1 0 .255c-.008.378.137.75.43.991l1.004.827c.424.35.534.955.26 1.43l-1.298 2.247a1.125 1.125 0 0 1-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.47 6.47 0 0 1-.22.128c-.331.183-.581.495-.644.869l-.213 1.281c-.09.543-.56.94-1.11.94h-2.594c-.55 0-1.019-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 0 1-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 0 1-1.369-.49l-1.297-2.247a1.125 1.125 0 0 1 .26-1.431l1.004-.827c.292-.24.437-.613.43-.991a6.932 6.932 0 0 1 0-.255c.007-.38-.138-.751-.43-.992l-1.004-.827a1.125 1.125 0 0 1-.26-1.43l1.297-2.247a1.125 1.125 0 0 1 1.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.086.22-.128.332-.183.582-.495.644-.869l.214-1.28Z"
					/>
					<path
						stroke-linecap="round"
						stroke-linejoin="round"
						d="M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z"
					/>
				</svg>
				<div class="flex items-center">{$i18n.t('Settings')}</div>
			</DropdownMenu.Item> -->

			{#if $mobile}
				<DropdownMenu.Item
					class="flex gap-2 items-center px-3 py-2 text-sm  cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-800 rounded-md"
					id="chat-controls-button"
					on:click={async () => {
						await showControls.set(true);
						await showOverview.set(false);
						await showArtifacts.set(false);
					}}
				>
					<AdjustmentsHorizontal className=" size-4" strokeWidth="0.5" />
					<div class="flex items-center">{$i18n.t('Controls')}</div>
				</DropdownMenu.Item>
			{/if}

			{#if !$temporaryChatEnabled}
				<DropdownMenu.Item
					class="flex gap-2 items-center px-3 py-2 text-sm  cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-800 rounded-md"
					id="chat-share-button"
					on:click={() => {
						shareHandler();
					}}
				>
					<svg
						xmlns="http://www.w3.org/2000/svg"
						viewBox="0 0 24 24"
						fill="currentColor"
						class="size-4"
					>
						<path
							fill-rule="evenodd"
							d="M15.75 4.5a3 3 0 1 1 .825 2.066l-8.421 4.679a3.002 3.002 0 0 1 0 1.51l8.421 4.679a3 3 0 1 1-.729 1.31l-8.421-4.678a3 3 0 1 1 0-4.132l8.421-4.679a3 3 0 0 1-.096-.755Z"
							clip-rule="evenodd"
						/>
					</svg>
					<div class="flex items-center">{$i18n.t('Share')}</div>
				</DropdownMenu.Item>
			{/if}

			<DropdownMenu.Item
				class="flex gap-2 items-center px-3 py-2 text-sm  cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-800 rounded-md"
				id="chat-overview-button"
				on:click={async () => {
					await showControls.set(true);
					await showOverview.set(true);
					await showArtifacts.set(false);
				}}
			>
				<Map className=" size-4" strokeWidth="1.5" />
				<div class="flex items-center">{$i18n.t('Overview')}</div>
			</DropdownMenu.Item>

			<DropdownMenu.Item
				class="flex gap-2 items-center px-3 py-2 text-sm  cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-800 rounded-md"
				id="chat-overview-button"
				on:click={async () => {
					await showControls.set(true);
					await showArtifacts.set(true);
					await showOverview.set(false);
				}}
			>
				<Cube className=" size-4" strokeWidth="1.5" />
				<div class="flex items-center">{$i18n.t('Artifacts')}</div>
			</DropdownMenu.Item>

			<DropdownMenu.Sub>
				<DropdownMenu.SubTrigger
					class="flex gap-2 items-center px-3 py-2 text-sm  cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-800 rounded-md"
				>
					<svg
						xmlns="http://www.w3.org/2000/svg"
						fill="none"
						viewBox="0 0 24 24"
						stroke-width="1.5"
						stroke="currentColor"
						class="size-4"
					>
						<path
							stroke-linecap="round"
							stroke-linejoin="round"
							d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3"
						/>
					</svg>

					<div class="flex items-center">{$i18n.t('Download')}</div>
				</DropdownMenu.SubTrigger>
				<DropdownMenu.SubContent
					class="w-full rounded-xl px-1 py-1.5 z-50 bg-white dark:bg-gray-850 dark:text-white shadow-lg"
					transition={flyAndScale}
					sideOffset={8}
				>
					<DropdownMenu.Item
						class="flex gap-2 items-center px-3 py-2 text-sm  cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-800 rounded-md"
						on:click={() => {
							downloadJSONExport();
						}}
					>
						<div class="flex items-center line-clamp-1">{$i18n.t('Export chat (.json)')}</div>
					</DropdownMenu.Item>
					<DropdownMenu.Item
						class="flex gap-2 items-center px-3 py-2 text-sm  cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-800 rounded-md"
						on:click={() => {
							downloadTxt();
						}}
					>
						<div class="flex items-center line-clamp-1">{$i18n.t('Plain text (.txt)')}</div>
					</DropdownMenu.Item>

					<DropdownMenu.Item
						class="flex gap-2 items-center px-3 py-2 text-sm  cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-800 rounded-md"
						on:click={() => {
							downloadPdf();
						}}
					>
						<div class="flex items-center line-clamp-1">{$i18n.t('PDF document (.pdf)')}</div>
					</DropdownMenu.Item>
				</DropdownMenu.SubContent>
			</DropdownMenu.Sub>

			<DropdownMenu.Item
				class="flex gap-2 items-center px-3 py-2 text-sm  cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-800 rounded-md"
				id="chat-copy-button"
				on:click={async () => {
					if (await copyChatToClipboard()) {
						toast.success($i18n.t('Copied to clipboard'));
					}
				}}
			>
				<Clipboard className=" size-4" strokeWidth="1.5" />
				<div class="flex items-center">{$i18n.t('Copy')}</div>
			</DropdownMenu.Item>

			{#if !$temporaryChatEnabled}
				<hr class="border-gray-100 dark:border-gray-850 my-0.5" />

				<div class="flex p-1">
					<Tags chatId={chat.id} />
				</div>
			{/if}
		</DropdownMenu.Content>
	</div>
</Dropdown>
